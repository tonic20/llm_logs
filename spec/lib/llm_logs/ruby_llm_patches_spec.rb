require "spec_helper"
require "aws-eventstream"
require "llm_logs/ruby_llm_patches"

RSpec.describe LlmLogs::RubyLLMPatches do
  let(:runtime) { "https://bedrock-runtime.us-west-2.amazonaws.com" }
  let(:claude) { "us.anthropic.claude-haiku-4-5-20251001-v1:0" }

  around do |example|
    config = RubyLLM.config
    keys = %i[bedrock_api_key bedrock_secret_key bedrock_region max_retries retry_interval]
    saved = keys.to_h { |k| [k, config.public_send(k)] }
    RubyLLM.configure do |c|
      c.bedrock_api_key = "AKIDEXAMPLE"
      c.bedrock_secret_key = "secret"
      c.bedrock_region = "us-west-2"
      c.max_retries = 1
      c.retry_interval = 0
    end
    described_class.install!
    LlmLogs.enabled = false
    example.run
  ensure
    LlmLogs.enabled = true
    saved.each { |k, v| config.public_send(:"#{k}=", v) }
  end

  let(:converse_ok) do
    {status: 200, headers: {"Content-Type" => "application/json"},
     body: {output: {message: {role: "assistant", content: [{text: "OK"}]}}, stopReason: "end_turn",
            usage: {inputTokens: 1, outputTokens: 1}}.to_json}
  end

  describe "BedrockSigV4: every attempt is signed when it is sent" do
    # SigV4 signatures expire five minutes after X-Amz-Date. A request that times out after
    # request_timeout (300s by default) and is retried with the first attempt's headers is
    # rejected with "Signature expired".
    let(:started_at) { Time.utc(2026, 10, 2, 14, 12, 2) }
    let(:offset) { [0] }
    let(:attempts) { [] }

    before do
      now = started_at
      allow(Time).to receive(:now) { now + offset.first }
    end

    # Records each attempt; the first times out and moves the clock 6 minutes on.
    def timeout_then(response)
      lambda do |request|
        attempts << {date: request.headers["X-Amz-Date"], auth: request.headers["Authorization"],
                     token: request.headers["X-Amz-Security-Token"], body: request.body}
        if attempts.size == 1
          offset[0] = 360
          raise Net::ReadTimeout
        end
        response
      end
    end

    # What ruby_llm itself signs for this request at the current (stubbed) time.
    def expected_auth(path, body, service: "bedrock", base_url: runtime)
      RubyLLM::Providers::Bedrock.new(RubyLLM.config)
        .sign_headers("POST", path, body, base_url: base_url, service: service)["Authorization"]
    end

    def frame(event_type, payload)
      Aws::EventStream::Encoder.new.encode_message(Aws::EventStream::Message.new(
        headers: {":event-type" => Aws::EventStream::HeaderValue.new(value: event_type, type: "string"),
                  ":message-type" => Aws::EventStream::HeaderValue.new(value: "event", type: "string")},
        payload: StringIO.new(payload.to_json)
      ))
    end

    it "re-signs a sync Converse retry at the time it is sent, over the sent body" do
      stub_request(:post, "#{runtime}/model/#{claude}/converse").to_return(timeout_then(converse_ok))

      chat = RubyLLM.chat(model: claude, provider: :bedrock, assume_model_exists: true)
      expect(chat.ask("Reply with OK.").content).to eq("OK")

      expect(attempts.map { |a| a[:date] }).to eq(%w[20261002T141202Z 20261002T141802Z])
      expect(attempts.map { |a| a[:auth] }.uniq.size).to eq(2)
      # the retry carries exactly the signature ruby_llm would compute now for this path and body
      expect(attempts.last[:auth]).to eq(expected_auth("/model/#{claude}/converse", attempts.last[:body]))
    end

    it "re-signs a converse-stream retry (nothing was streamed before the timeout)" do
      body = [frame("contentBlockDelta", {contentBlockIndex: 0, delta: {text: "OK"}}),
              frame("messageStop", {stopReason: "end_turn"}),
              frame("metadata", {usage: {inputTokens: 1, outputTokens: 1}})].join
      stub_request(:post, "#{runtime}/model/#{claude}/converse-stream")
        .to_return(timeout_then(status: 200, body: body, headers: {"Content-Type" => "application/vnd.amazon.eventstream"}))

      chunks = []
      RubyLLM.chat(model: claude, provider: :bedrock, assume_model_exists: true).ask("hi") { |c| chunks << c.content }

      expect(chunks.join).to eq("OK")
      expect(attempts.map { |a| a[:date] }).to eq(%w[20261002T141202Z 20261002T141802Z])
      expect(attempts.last[:auth]).to eq(expected_auth("/model/#{claude}/converse-stream", attempts.last[:body]))
    end

    it "re-signs a count-tokens retry" do
      stub_request(:post, "#{runtime}/model/#{claude}/count-tokens")
        .to_return(timeout_then(status: 200, body: {inputTokens: 7}.to_json, headers: {"Content-Type" => "application/json"}))

      tokens = RubyLLM.chat(model: claude, provider: :bedrock, assume_model_exists: true).count_tokens("hi")

      expect(tokens).to eq(7)
      expect(attempts.map { |a| a[:date] }).to eq(%w[20261002T141202Z 20261002T141802Z])
    end

    it "signs an escaped inference-profile ARN path the way ruby_llm does" do
      arn = "arn:aws:bedrock:us-west-2:123456789012:application-inference-profile/abc123"
      stub_request(:post, "#{runtime}/model/#{arn.gsub("/", "%2F")}/converse").to_return(timeout_then(converse_ok))

      RubyLLM.chat(model: arn, provider: :bedrock, assume_model_exists: true).ask("hi")

      expect(attempts.last[:auth]).to eq(expected_auth("/model/#{arn.gsub("/", "%2F")}/converse", attempts.last[:body]))
      expect(attempts.map { |a| a[:date] }.uniq.size).to eq(2)
    end

    it "keeps the bedrock-mantle signing service for mantle requests" do
      mantle = "https://bedrock-mantle.us-west-2.api.aws"
      anthropic_ok = {status: 200, headers: {"Content-Type" => "application/json"},
                      body: {id: "msg_1", type: "message", role: "assistant", model: "anthropic.claude-sonnet-4-6",
                             content: [{type: "text", text: "OK"}], stop_reason: "end_turn",
                             usage: {input_tokens: 1, output_tokens: 1}}.to_json}
      stub_request(:post, %r{\A#{mantle}/}).to_return(timeout_then(anthropic_ok))

      RubyLLM.chat(model: "anthropic.claude-sonnet-4-6", provider: :bedrock).ask("hi")

      expect(attempts.map { |a| a[:auth] }).to all(include("/bedrock-mantle/aws4_request"))
      expect(attempts.map { |a| a[:date] }).to eq(%w[20261002T141202Z 20261002T141802Z])
    end
  end

  describe "ConverseOpenAIReasoning: GPT effort is sent as reasoning.effort" do
    def reasoning_fields(model, **thinking)
      chat = RubyLLM.chat(model: model, provider: :bedrock, assume_model_exists: true)
      chat.with_thinking(**thinking) if thinking.any?
      chat.add_message(role: :user, content: "hi")
      chat.render[:additionalModelRequestFields]
    end

    it "nests effort under reasoning for OpenAI GPT models on Converse" do
      expect(reasoning_fields("us.openai.gpt-6-sol", effort: :low)).to eq(reasoning: {effort: "low"})
      expect(reasoning_fields("us.openai.gpt-6-luna", effort: :high)).to eq(reasoning: {effort: "high"})
      expect(reasoning_fields("us.openai.gpt-5.6-sol", effort: :medium)).to eq(reasoning: {effort: "medium"})
      expect(reasoning_fields("global.openai.gpt-6-astra", effort: :xhigh)).to eq(reasoning: {effort: "xhigh"})
    end

    it "passes the none tier through for GPT" do
      expect(reasoning_fields("us.openai.gpt-6-sol", effort: :none)).to eq(reasoning: {effort: "none"})
    end

    it "sends nothing for GPT when thinking is not configured" do
      expect(reasoning_fields("us.openai.gpt-6-sol")).to be_nil
    end

    it "keeps upstream behaviour for Claude, Nova and gpt-oss" do
      expect(reasoning_fields("us.anthropic.claude-sonnet-4-6", effort: :low))
        .to eq(reasoning_config: {type: "enabled", budget_tokens: 1024})
      expect(reasoning_fields("us.amazon.nova-2-lite-v1:0", effort: :medium))
        .to eq(reasoningConfig: {type: "enabled", maxReasoningEffort: "medium"})
      expect(reasoning_fields("us.openai.gpt-oss-120b-1:0", effort: :low)).to eq(reasoning_effort: "low")
    end

    it "puts the nested shape on the wire" do
      stub = stub_request(:post, "#{runtime}/model/us.openai.gpt-6-sol/converse")
        .with { |req| JSON.parse(req.body)["additionalModelRequestFields"] == {"reasoning" => {"effort" => "low"}} }
        .to_return(converse_ok)

      RubyLLM.chat(model: "us.openai.gpt-6-sol", provider: :bedrock, assume_model_exists: true)
        .with_thinking(effort: :low).ask("hi")

      expect(stub).to have_been_requested
    end
  end

  describe "RetrySSLError: TLS handshake failures are retried" do
    it "retries a Faraday::SSLError and succeeds" do
      stub_request(:post, "#{runtime}/model/#{claude}/converse")
        .to_raise(OpenSSL::SSL::SSLError.new("SSL_connect returned=1 errno=0 state=error: unexpected eof while reading"))
        .then.to_return(converse_ok)

      response = RubyLLM.chat(model: claude, provider: :bedrock, assume_model_exists: true).ask("hi")

      expect(response.content).to eq("OK")
      expect(a_request(:post, "#{runtime}/model/#{claude}/converse")).to have_been_made.twice
    end
  end

  describe ".install!" do
    it "is idempotent and reports the installed patches" do
      expect(described_class.install!).to eq(described_class::PATCHES)
      expect(RubyLLM::Transport::Connection.ancestors.count(described_class::RetrySSLError)).to eq(1)
    end
  end
end
