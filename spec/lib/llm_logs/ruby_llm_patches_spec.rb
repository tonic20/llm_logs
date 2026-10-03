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

  # ruby_llm sends an unregistered, unsuffixed id with a region prefix it does not know
  # ("in.") to bedrock-mantle; an app that registers it without a mantle endpoint (as a
  # Bedrock catalog does) gets Converse. Stands in for that registration.
  def route_in_prefix_to_converse
    allow(RubyLLM::Providers::Bedrock::Models).to receive(:mantle_model?)
      .and_wrap_original { |original, id, models| !id.start_with?("in.") && original.call(id, models) }
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

  describe "ConverseReasoningConfig: effort is the reasoning_config value (backport of ruby_llm#1025)" do
    def reasoning_fields(model, thinking = nil, assume_model_exists: true)
      chat = RubyLLM.chat(model: model, provider: :bedrock, assume_model_exists: assume_model_exists)
      chat.with_thinking(thinking) unless thinking.nil?
      chat.add_message(role: :user, content: "hi")
      chat.render[:additionalModelRequestFields]
    end

    # GPT-6 Sol as an app's Bedrock catalog registers it (spoton-api's bedrock_models.json):
    # effort values including "none", but no Converse additionalRequestFieldsSchema. ruby_llm
    # 2.0.0's packaged registry does not list GPT-6 Sol/Luna at all.
    def register_like_app_catalog(id)
      allow(RubyLLM::Model).to receive(:default).and_wrap_original do |original, model_id, provider|
        next original.call(model_id, provider) unless model_id == id

        RubyLLM::Model.new(id: id, name: id, provider: provider, capabilities: %w[reasoning streaming],
          metadata: {reasoning_options: [{type: "effort", values: %w[none low medium high xhigh max]}]})
      end
    end

    context "when the model publishes a reasoning_config enum (upstream rule)" do
      it "sends the effort as the reasoning_config value" do
        expect(reasoning_fields("us.openai.gpt-5.6-sol", {effort: :low})).to eq(reasoning_config: "low")
        expect(reasoning_fields("us.openai.gpt-6-astra", {effort: :xhigh})).to eq(reasoning_config: "xhigh")
      end

      it "applies to any vendor that publishes the enum, not only OpenAI" do
        expect(reasoning_fields("us.xai.grok-4.6", {effort: :medium})).to eq(reasoning_config: "medium")
      end

      it "reads the schema from another registry entry for the same foundation model" do
        # global.openai.gpt-5.6-sol has no Converse metadata; us.openai.gpt-5.6-sol has the schema.
        expect(reasoning_fields("global.openai.gpt-5.6-sol", {effort: :none})).to eq(reasoning_config: "none")
      end

      it "turns reasoning off with reasoning_config none for with_thinking(false)" do
        # The registered entry's effort values include "none", so thinking off resolves to effort none.
        expect(reasoning_fields("us.openai.gpt-5.6-sol", false, assume_model_exists: false))
          .to eq(reasoning_config: "none")
      end
    end

    context "when an OpenAI GPT id has no published schema (fallback until the registry lists it)" do
      it "still sends the effort as the reasoning_config value" do
        expect(reasoning_fields("us.openai.gpt-6-sol", {effort: :low})).to eq(reasoning_config: "low")
        expect(reasoning_fields("us.openai.gpt-6-luna", {effort: :high})).to eq(reasoning_config: "high")
      end

      it "passes the none tier through" do
        expect(reasoning_fields("us.openai.gpt-6-sol", {effort: :none})).to eq(reasoning_config: "none")
      end

      it "turns reasoning off with reasoning_config none for with_thinking(false) on the real path" do
        register_like_app_catalog("us.openai.gpt-6-sol")
        expect(reasoning_fields("us.openai.gpt-6-sol", false)).to eq(reasoning_config: "none")
      end

      it "recognises GPT under a region prefix ruby_llm does not strip" do
        # Converse::REGION_PREFIXES has no "in", so foundation_model_id leaves "in.openai...." whole.
        route_in_prefix_to_converse
        expect(reasoning_fields("in.openai.gpt-6-sol", {effort: :low})).to eq(reasoning_config: "low")
        expect(reasoning_fields("in.openai.gpt-oss-120b-1:0", {effort: :low})).to eq(reasoning_effort: "low")
      end
    end

    it "sends nothing when thinking is not configured" do
      expect(reasoning_fields("us.openai.gpt-6-sol")).to be_nil
      expect(reasoning_fields("us.openai.gpt-5.6-sol")).to be_nil
    end

    it "keeps upstream behaviour for an explicit budget, Claude, Nova and gpt-oss" do
      expect(reasoning_fields("us.openai.gpt-6-sol", {budget: 2048}))
        .to eq(reasoning_config: {type: "enabled", budget_tokens: 2048})
      expect(reasoning_fields("us.anthropic.claude-sonnet-4-6", {effort: :low}))
        .to eq(reasoning_config: {type: "enabled", budget_tokens: 1024})
      expect(reasoning_fields("us.amazon.nova-2-lite-v1:0", {effort: :medium}))
        .to eq(reasoningConfig: {type: "enabled", maxReasoningEffort: "medium"})
      expect(reasoning_fields("us.openai.gpt-oss-120b-1:0", {effort: :low})).to eq(reasoning_effort: "low")
    end

    it "puts reasoning_config on the wire" do
      stub = stub_request(:post, "#{runtime}/model/us.openai.gpt-6-sol/converse")
        .with { |req| JSON.parse(req.body)["additionalModelRequestFields"] == {"reasoning_config" => "low"} }
        .to_return(converse_ok)

      RubyLLM.chat(model: "us.openai.gpt-6-sol", provider: :bedrock, assume_model_exists: true)
        .with_thinking(effort: :low).ask("hi")

      expect(stub).to have_been_requested
    end
  end

  describe "ConverseClaudeAdaptiveThinking: adaptive-only Claude thinks adaptively on Converse" do
    # Sonnet 5 and Opus 4.8 advertise effort and no budget_tokens; Bedrock rejects
    # reasoning_config enabled for them ("thinking.type.enabled" is not supported).
    def reasoning_fields(model, thinking = nil)
      chat = RubyLLM.chat(model: model, provider: :bedrock, assume_model_exists: true)
      chat.with_thinking(thinking) unless thinking.nil?
      chat.add_message(role: :user, content: "hi")
      chat.render[:additionalModelRequestFields]
    end

    it "sends adaptive thinking with the effort as output_config for Sonnet 5" do
      expect(reasoning_fields("us.anthropic.claude-sonnet-5", effort: :low))
        .to eq(thinking: {type: "adaptive"}, output_config: {effort: "low"})
      expect(reasoning_fields("us.anthropic.claude-sonnet-5", effort: :max))
        .to eq(thinking: {type: "adaptive"}, output_config: {effort: "max"})
      expect(reasoning_fields("global.anthropic.claude-opus-4-8", effort: :xhigh))
        .to eq(thinking: {type: "adaptive"}, output_config: {effort: "xhigh"})
    end

    it "turns adaptive thinking on without an effort when thinking is enabled alone" do
      # with_thinking(true) resolves to {enabled: true} for a model with a toggle and no default effort.
      expect(reasoning_fields("us.anthropic.claude-sonnet-5", true)).to eq(thinking: {type: "adaptive"})
    end

    it "sends nothing for the none tier" do
      expect(reasoning_fields("us.anthropic.claude-sonnet-5", effort: :none)).to be_nil
    end

    it "recognises adaptive-only Claude under a region prefix ruby_llm does not strip" do
      # Unregistered: its reasoning options come from another entry for the same foundation model.
      route_in_prefix_to_converse
      expect(reasoning_fields("in.anthropic.claude-sonnet-5", effort: :medium))
        .to eq(thinking: {type: "adaptive"}, output_config: {effort: "medium"})
    end

    it "keeps upstream behaviour for an explicit budget and for thinking turned off" do
      expect(reasoning_fields("us.anthropic.claude-sonnet-5", budget: 2048))
        .to eq(reasoning_config: {type: "enabled", budget_tokens: 2048})
      expect(reasoning_fields("us.anthropic.claude-sonnet-5", false)).to eq(reasoning_config: {type: "disabled"})
    end

    it "keeps upstream budgets for budget-style Claude" do
      expect(reasoning_fields("us.anthropic.claude-sonnet-4-6", effort: :low))
        .to eq(reasoning_config: {type: "enabled", budget_tokens: 1024})
      expect(reasoning_fields(claude, budget: 2048)).to eq(reasoning_config: {type: "enabled", budget_tokens: 2048})
      expect(reasoning_fields(claude, effort: :low)).to eq(reasoning_config: {type: "enabled", budget_tokens: 1024})
    end

    it "leaves GPT to ConverseReasoningConfig" do
      expect(reasoning_fields("us.openai.gpt-6-sol", effort: :low)).to eq(reasoning_config: "low")
    end

    it "puts the adaptive shape on the wire" do
      stub = stub_request(:post, "#{runtime}/model/us.anthropic.claude-sonnet-5/converse")
        .with { |req|
          JSON.parse(req.body)["additionalModelRequestFields"] ==
            {"thinking" => {"type" => "adaptive"}, "output_config" => {"effort" => "low"}}
        }
        .to_return(converse_ok)

      RubyLLM.chat(model: "us.anthropic.claude-sonnet-5", provider: :bedrock, assume_model_exists: true)
        .with_thinking(effort: :low).ask("hi")

      expect(stub).to have_been_requested
    end
  end

  describe "ConverseForeignReasoning: reasoning is replayed only to a model of the same family" do
    let(:redacted) { {"reasoningContent" => {"redactedContent" => "gpt-encrypted"}} }
    let(:raw_text) { {"reasoningContent" => {"reasoningText" => {"text" => "raw", "signature" => "sig-3"}}} }

    # A chat Claude answered on Bedrock (thinking text + signature, a signature-only row with
    # thinking_text "" after a data migration, raw reasoningText blocks) and GPT then continued
    # (raw redactedContent: its own encrypted reasoning; one message mixing both kinds).
    def mixed_history(chat)
      chat.add_message(role: :user, content: "Q1")
      chat.add_message(role: :assistant, content: "A1",
        thinking: RubyLLM::Thinking.build(text: "thought one", signature: "sig-1"))
      chat.add_message(role: :user, content: "Q2")
      chat.add_message(role: :assistant, content: "A2", thinking: RubyLLM::Thinking.build(text: "", signature: "sig-2"))
      chat.add_message(role: :user, content: "Q3")
      chat.add_message(role: :assistant, content: "A3", raw_reasoning: {"converse" => [raw_text]})
      chat.add_message(role: :user, content: "Q4")
      chat.add_message(role: :assistant, content: "A4", raw_reasoning: {"converse" => [redacted]})
      chat.add_message(role: :user, content: "Q5")
      chat.add_message(role: :assistant, content: "A5", raw_reasoning: {"converse" => [raw_text, redacted]})
      chat
    end

    # Sends the history plus a new question to +model+ and returns the assistant content blocks sent.
    def assistant_content_sent(model)
      bodies = []
      # any model path: ruby_llm may resolve the id to its catalog's regional profile
      stub_request(:post, %r{\A#{runtime}/model/[^/]+/converse\z})
        .to_return { |req| bodies << JSON.parse(req.body) && converse_ok }

      mixed_history(RubyLLM.chat(model: model, provider: :bedrock, assume_model_exists: true)).ask("Q6")

      expect(bodies.size).to eq(1)
      bodies.first["messages"].select { |m| m["role"] == "assistant" }.map { |m| m["content"] }
    end

    let(:non_anthropic_content) do
      [[{"text" => "A1"}], [{"text" => "A2"}], [{"text" => "A3"}],
       [redacted, {"text" => "A4"}], [redacted, {"text" => "A5"}]]
    end

    it "sends an OpenAI GPT model its redactedContent but no reasoningText or thinking fallback" do
      expect(assistant_content_sent("us.openai.gpt-6-sol")).to eq(non_anthropic_content)
    end

    it "applies the same rule to other non-Anthropic Converse models" do
      expect(assistant_content_sent("us.amazon.nova-2-lite-v1:0")).to eq(non_anthropic_content)
    end

    it "keeps replaying all reasoning to Claude models (upstream behaviour)" do
      content = assistant_content_sent("us.anthropic.claude-sonnet-4-6")

      expect(content).to eq([
        [{"reasoningContent" => {"reasoningText" => {"text" => "thought one", "signature" => "sig-1"}}}, {"text" => "A1"}],
        [{"reasoningContent" => {"reasoningText" => {"text" => "", "signature" => "sig-2"}}}, {"text" => "A2"}],
        [raw_text, {"text" => "A3"}],
        [redacted, {"text" => "A4"}],
        [raw_text, redacted, {"text" => "A5"}]
      ])
    end

    it "keeps replaying to Claude under any region prefix" do
      [claude, "global.anthropic.claude-sonnet-4-6", "eu.anthropic.claude-sonnet-4-6"].each do |model|
        expect(assistant_content_sent(model).first(3).map(&:first)).to all(have_key("reasoningContent"))
      end
    end

    it "treats a model under a region prefix ruby_llm does not strip as Anthropic" do
      route_in_prefix_to_converse
      expect(assistant_content_sent("in.anthropic.claude-sonnet-4-6").first(3).map(&:first))
        .to all(have_key("reasoningContent"))
    end

    it "keeps upstream behaviour for an application inference profile, whose id names no model" do
      arn = "arn:aws:bedrock:us-west-2:123456789012:application-inference-profile/abc123"
      expect(assistant_content_sent(arn).first(3).map(&:first)).to all(have_key("reasoningContent"))
    end

    context "when the message names the model that produced it" do
      # Each assistant message carries the model that produced it, as RubyLLM::Message#model
      # does for replies and for rows restored from ruby_llm_usages.
      def produced_history(chat, producer)
        chat.add_message(role: :user, content: "Q1")
        chat.add_message(role: :assistant, content: "A1", model: producer,
          thinking: RubyLLM::Thinking.build(text: "thought one", signature: "sig-1"))
        chat.add_message(role: :user, content: "Q2")
        # a legacy row: signature only, thinking_text "" after the data migration
        chat.add_message(role: :assistant, content: "A2", model: producer,
          thinking: RubyLLM::Thinking.build(text: "", signature: "sig-2"))
        chat.add_message(role: :user, content: "Q3")
        chat.add_message(role: :assistant, content: "A3", model: producer,
          raw_reasoning: {"converse" => [raw_text, redacted]})
        chat
      end

      def produced_content_sent(producer:, target:)
        bodies = []
        stub_request(:post, %r{\A#{runtime}/model/[^/]+/converse\z})
          .to_return { |req| bodies << JSON.parse(req.body) && converse_ok }

        produced_history(RubyLLM.chat(model: target, provider: :bedrock, assume_model_exists: true), producer)
          .ask("Q4")

        expect(bodies.size).to eq(1)
        bodies.first["messages"].select { |m| m["role"] == "assistant" }.map { |m| m["content"] }
      end

      let(:no_reasoning) { [[{"text" => "A1"}], [{"text" => "A2"}], [{"text" => "A3"}]] }

      it "drops GPT-produced reasoning when Claude continues the chat" do
        expect(produced_content_sent(producer: "us.openai.gpt-6-sol", target: "us.anthropic.claude-sonnet-5"))
          .to eq(no_reasoning)
      end

      it "drops reasoning GPT produced under an unstripped region prefix" do
        expect(produced_content_sent(producer: "in.openai.gpt-6-sol", target: "us.anthropic.claude-sonnet-5"))
          .to eq(no_reasoning)
      end

      it "replays Claude-produced reasoning to Claude (upstream behaviour)" do
        expect(produced_content_sent(producer: "us.anthropic.claude-sonnet-5", target: "global.anthropic.claude-sonnet-5"))
          .to eq([
            [{"reasoningContent" => {"reasoningText" => {"text" => "thought one", "signature" => "sig-1"}}}, {"text" => "A1"}],
            [{"reasoningContent" => {"reasoningText" => {"text" => "", "signature" => "sig-2"}}}, {"text" => "A2"}],
            [raw_text, redacted, {"text" => "A3"}]
          ])
      end

      it "drops Claude-produced reasoning, redactedContent included, when GPT continues the chat" do
        expect(produced_content_sent(producer: "us.anthropic.claude-sonnet-5", target: "us.openai.gpt-6-sol"))
          .to eq(no_reasoning)
      end

      it "keeps GPT's own redactedContent for GPT, without reasoningText or the thinking fallback" do
        expect(produced_content_sent(producer: "us.openai.gpt-6-sol", target: "us.openai.gpt-6-luna"))
          .to eq([[{"text" => "A1"}], [{"text" => "A2"}], [redacted, {"text" => "A3"}]])
      end

      it "drops reasoning another vendor produced" do
        expect(produced_content_sent(producer: "us.amazon.nova-2-lite-v1:0", target: "us.openai.gpt-6-sol"))
          .to eq(no_reasoning)
      end

      it "keeps the producer-unknown rule for an application inference profile producer" do
        arn = "arn:aws:bedrock:us-west-2:123456789012:application-inference-profile/abc123"
        expect(produced_content_sent(producer: arn, target: "us.anthropic.claude-sonnet-5").map(&:first))
          .to all(have_key("reasoningContent"))
      end
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
