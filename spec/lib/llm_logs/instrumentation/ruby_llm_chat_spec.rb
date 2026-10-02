require "spec_helper"
require "aws-eventstream"
require "llm_logs/instrumentation/ruby_llm_chat"

RSpec.describe LlmLogs::Instrumentation::RubyLlmChat do
  let(:model) { "us.anthropic.claude-haiku-4-5-20251001-v1:0" }
  let(:host) { "https://bedrock-runtime.us-west-2.amazonaws.com" }

  let(:weather_tool) do
    Class.new(RubyLLM::Tool) do
      def self.name = "Weather"
      description "Current weather for a city"
      parameter :city, type: :string, description: "City name"

      def execute(city:)
        raise ArgumentError, "no weather for #{city}" if city == "Atlantis"

        {city: city, temp_c: 21}
      end
    end
  end

  around do |example|
    config = RubyLLM.config
    saved = %i[bedrock_api_key bedrock_secret_key bedrock_region max_retries retry_interval].to_h { |k| [k, config.public_send(k)] }
    RubyLLM.configure do |c|
      c.bedrock_api_key = "AKIDEXAMPLE"
      c.bedrock_secret_key = "secret"
      c.bedrock_region = "us-west-2"
      c.max_retries = 2
      c.retry_interval = 0
    end
    described_class.install!
    example.run
  ensure
    saved.each { |k, v| config.public_send(:"#{k}=", v) }
    Fiber[:llm_logs_trace] = nil
    Fiber[:llm_logs_span] = nil
  end

  def converse_json(content:, stop:, usage:)
    {output: {message: {role: "assistant", content: content}}, stopReason: stop, usage: usage}.to_json
  end

  def tool_round(city: "Berlin")
    converse_json(
      content: [{text: "Let me check."}, {toolUse: {toolUseId: "tooluse_1", name: "weather", input: {city: city}}}],
      stop: "tool_use",
      usage: {inputTokens: 120, outputTokens: 30, cacheReadInputTokens: 1000, cacheWriteInputTokens: 200}
    )
  end

  def answer_round
    converse_json(
      content: [{text: "It is 21C in Berlin."}],
      stop: "end_turn",
      usage: {inputTokens: 180, outputTokens: 12, cacheReadInputTokens: 1200}
    )
  end

  def json_response(body) = {status: 200, body: body, headers: {"Content-Type" => "application/json"}}

  def stub_converse(*responses, path: "converse", model_id: model)
    stub_request(:post, "#{host}/model/#{model_id}/#{path}").to_return(*responses)
  end

  def frame(event_type, payload)
    message = Aws::EventStream::Message.new(
      headers: {
        ":event-type" => Aws::EventStream::HeaderValue.new(value: event_type, type: "string"),
        ":message-type" => Aws::EventStream::HeaderValue.new(value: "event", type: "string"),
        ":content-type" => Aws::EventStream::HeaderValue.new(value: "application/json", type: "string")
      },
      payload: StringIO.new(payload.to_json)
    )
    Aws::EventStream::Encoder.new.encode_message(message)
  end

  def stream_body(*events)
    {status: 200, body: events.map { |type, payload| frame(type, payload) }.join,
     headers: {"Content-Type" => "application/vnd.amazon.eventstream"}}
  end

  def span_rows(trace)
    trace.spans.order(:id).map do |s|
      {name: s.name, type: s.span_type, status: s.status, model: s.model, provider: s.provider,
       in: s.input_tokens, out: s.output_tokens, cached: s.cached_tokens, cost: s.cost&.to_f,
       meta: s.metadata.except("tools"), output: s.output, error: s.error_message,
       input_roles: s.span_type == "llm" ? s.input.map { |m| m["role"] } : s.input,
       parent: s.parent_span_id}
    end
  end

  def dump(label, trace)
    puts "\n== #{label} (trace #{trace.status}, tokens in=#{trace.total_input_tokens} out=#{trace.total_output_tokens} " \
         "cached=#{trace.total_cached_tokens} cost=#{trace.total_cost.to_f})"
    span_rows(trace).each { |row| puts "  #{row.inspect}" }
  end

  it "records one llm span per provider round and one tool span per tool call (sync)" do
    stub_converse(json_response(tool_round), json_response(answer_round))

    trace = nil
    LlmLogs.trace("weather_question") do |t|
      trace = t
      chat = RubyLLM.chat(model: model, provider: :bedrock, assume_model_exists: true)
      chat.with_instructions("Be brief.").with_tools(weather_tool)
      expect(chat.ask("Weather in Berlin?").content).to eq("It is 21C in Berlin.")
    end
    trace.reload
    dump("sync", trace)

    llm1, tool, llm2 = trace.spans.order(:id).to_a
    expect([llm1.name, tool.name, llm2.name]).to eq(%w[chat.complete tool.weather chat.complete])
    expect([llm1, tool, llm2].map(&:parent_span_id)).to all(be_nil) # siblings, not nested

    expect(llm1.input.map { |m| m["role"] }).to eq(%w[system user])
    expect(llm1.output["tool_calls"]).to eq([{"id" => "tooluse_1", "name" => "weather", "arguments" => {"city" => "Berlin"}}])
    expect([llm1.input_tokens, llm1.output_tokens, llm1.cached_tokens]).to eq([120, 30, 1000])
    expect(llm1.metadata).to include("cache_write_tokens" => 200, "finish_reason" => "tool_calls")
    # us. Haiku 4.5 on Bedrock: 1.1 in / 5.5 out / 0.11 cache read / 1.375 cache write per million
    expect(llm1.cost.to_f).to be_within(1e-9).of((120 * 1.1 + 30 * 5.5 + 1000 * 0.11 + 200 * 1.375) / 1e6)

    expect(tool.input).to eq("city" => "Berlin")
    expect(tool.output).to eq("city" => "Berlin", "temp_c" => 21)

    expect(llm2.input.map { |m| m["role"] }).to eq(%w[system user assistant tool])
    expect(llm2.output["content"]).to eq("It is 21C in Berlin.")
    expect([llm2.input_tokens, llm2.output_tokens, llm2.cached_tokens]).to eq([180, 12, 1200])
    expect(trace.total_input_tokens).to eq(300)
    expect(trace.total_cost.to_f).to be_within(1e-6).of(llm1.cost.to_f + llm2.cost.to_f)
  end

  it "records the same shape when streaming" do
    stub_converse(
      stream_body(
        ["messageStart", {role: "assistant"}],
        ["contentBlockStart", {contentBlockIndex: 0, start: {toolUse: {toolUseId: "tooluse_1", name: "weather"}}}],
        ["contentBlockDelta", {contentBlockIndex: 0, delta: {toolUse: {input: '{"city":"Berlin"}'}}}],
        ["contentBlockStop", {contentBlockIndex: 0}],
        ["messageStop", {stopReason: "tool_use"}],
        ["metadata", {usage: {inputTokens: 120, outputTokens: 30, cacheReadInputTokens: 1000}, metrics: {latencyMs: 10}}]
      ),
      stream_body(
        ["messageStart", {role: "assistant"}],
        ["contentBlockDelta", {contentBlockIndex: 0, delta: {text: "It is 21C"}}],
        ["contentBlockDelta", {contentBlockIndex: 0, delta: {text: " in Berlin."}}],
        ["contentBlockStop", {contentBlockIndex: 0}],
        ["messageStop", {stopReason: "end_turn"}],
        ["metadata", {usage: {inputTokens: 180, outputTokens: 12}, metrics: {latencyMs: 10}}]
      ),
      path: "converse-stream"
    )

    chunks = []
    trace = nil
    LlmLogs.trace("weather_stream") do |t|
      trace = t
      chat = RubyLLM.chat(model: model, provider: :bedrock, assume_model_exists: true).with_tools(weather_tool)
      chat.ask("Weather in Berlin?") { |chunk| chunks << chunk.content if chunk.content }
    end
    trace.reload
    dump("streaming", trace)

    expect(chunks.join).to eq("It is 21C in Berlin.")
    expect(trace.spans.order(:id).map(&:name)).to eq(%w[chat.complete tool.weather chat.complete])
    llm1, _tool, llm2 = trace.spans.order(:id).to_a
    expect(llm1.metadata["streaming"]).to be(true)
    expect([llm1.input_tokens, llm1.output_tokens, llm1.cached_tokens]).to eq([120, 30, 1000])
    expect([llm2.input_tokens, llm2.output_tokens]).to eq([180, 12])
    expect(llm2.output["content"]).to eq("It is 21C in Berlin.")
  end

  it "records a failed round once, after the transport retries are exhausted" do
    error = {status: 500, body: {message: "boom"}.to_json, headers: {"Content-Type" => "application/json"}}
    stub_converse(error, error, error)

    trace = nil
    expect do
      LlmLogs.trace("failing") do |t|
        trace = t
        RubyLLM.chat(model: model, provider: :bedrock, assume_model_exists: true).ask("hi")
      end
    end.to raise_error(RubyLLM::ServerError)
    trace.reload
    dump("failure after retries", trace)

    expect(a_request(:post, "#{host}/model/#{model}/converse")).to have_been_made.times(3)
    span = trace.spans.sole
    expect(span.status).to eq("error")
    expect(span.error_message).to start_with("RubyLLM::ServerError")
    expect(span.metadata).to include("attempts" => 3)
    expect(span.cost).to be_nil
  end

  it "records one span per model when a fallback takes over" do
    error = {status: 500, body: {message: "boom"}.to_json, headers: {"Content-Type" => "application/json"}}
    stub_converse(error, error, error)
    stub_converse(json_response(answer_round), model_id: "us.anthropic.claude-sonnet-4-6")

    trace = nil
    LlmLogs.trace("fallback") do |t|
      trace = t
      RubyLLM.chat(model: model, provider: :bedrock, assume_model_exists: true)
        .with_fallbacks(RubyLLM.models.find("us.anthropic.claude-sonnet-4-6", provider: :bedrock))
        .ask("hi")
    end
    trace.reload
    dump("fallback", trace)

    primary, fallback = trace.spans.order(:id).to_a
    expect([primary.model, primary.status]).to eq([model, "error"])
    expect([fallback.model, fallback.status]).to eq(["us.anthropic.claude-sonnet-4-6", "ok"])
    expect(fallback.input_tokens).to eq(180)
  end

  it "records tokens but no cost for a model without registry pricing" do
    stub_converse(json_response(answer_round), model_id: "us.openai.gpt-6-sol")

    trace = nil
    LlmLogs.trace("unpriced") do |t|
      trace = t
      RubyLLM.chat(model: "us.openai.gpt-6-sol", provider: :bedrock, assume_model_exists: true).ask("hi")
    end
    trace.reload
    dump("unpriced model", trace)

    span = trace.spans.sole
    expect([span.input_tokens, span.output_tokens, span.cached_tokens]).to eq([180, 12, 1200])
    expect(span.cost).to be_nil
  end

  it "records a tool error on the tool span and re-raises it" do
    stub_converse(json_response(tool_round(city: "Atlantis")))

    trace = nil
    expect do
      LlmLogs.trace("tool_error") do |t|
        trace = t
        RubyLLM.chat(model: model, provider: :bedrock, assume_model_exists: true).with_tools(weather_tool).ask("Atlantis?")
      end
    end.to raise_error(ArgumentError, /no weather for Atlantis/)
    trace.reload
    dump("tool error", trace)

    tool = trace.spans.find_by!(span_type: "tool")
    expect(tool.status).to eq("error")
    expect(tool.error_message).to eq("ArgumentError: no weather for Atlantis")
  end

  it "records a schema answer as parsed JSON" do
    stub_converse(json_response(converse_json(content: [{text: '{"answer":"yes"}'}], stop: "end_turn",
                                              usage: {inputTokens: 5, outputTokens: 3})))
    schema = {name: "verdict", schema: {type: "object", properties: {answer: {type: "string"}}, required: ["answer"]}}

    trace = nil
    LlmLogs.trace("schema") do |t|
      trace = t
      response = RubyLLM.chat(model: model, provider: :bedrock, assume_model_exists: true).with_schema(schema).ask("?")
      expect(response.parsed).to eq("answer" => "yes")
    end
    expect(trace.reload.spans.sole.output["content"]).to eq("answer" => "yes")
  end

  it "does nothing while llm_logs is disabled" do
    stub_converse(json_response(answer_round))
    LlmLogs.enabled = false
    expect do
      RubyLLM.chat(model: model, provider: :bedrock, assume_model_exists: true).ask("hi")
    end.not_to change(LlmLogs::Span, :count)
  ensure
    LlmLogs.enabled = true
  end
end
