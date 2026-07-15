require "spec_helper"

RSpec.describe "LlmLogs::Batch provider resolution" do
  around do |ex|
    original = LlmLogs.configuration.bedrock_batch
    ex.run
    LlmLogs.configuration.bedrock_batch = original
    LlmLogs.batch_adapters.delete(:bedrock)
  end

  context "without bedrock configured" do
    before { LlmLogs.configuration.bedrock_batch = nil }

    it "resolves OpenAI models to :openai_responses and Claude models to nil" do
      allow(LlmLogs::Batch).to receive(:servable_by_batch_provider?).with("gpt-5.4-mini").and_return(true)
      allow(LlmLogs::Batch).to receive(:servable_by_batch_provider?).with("anthropic.claude-sonnet").and_return(false)
      expect(LlmLogs::Batch.batch_provider_for("gpt-5.4-mini")).to eq(:openai_responses)
      expect(LlmLogs::Batch.batch_provider_for("anthropic.claude-sonnet")).to be_nil
      expect(LlmLogs::Batch.min_records_for("gpt-5.4-mini")).to eq(0)
    end
  end

  context "with bedrock configured" do
    before do
      LlmLogs.configuration.bedrock_batch = LlmLogs::Configuration::BedrockBatch.new(
        role_arn: "arn:aws:iam::1:role/r", s3_bucket: "b", s3_prefix: "batch",
        min_records: 100, model_matcher: /\Aanthropic\./, region: "us-east-1"
      )
      LlmLogs.register_batch_adapter(:bedrock, Object.new)
    end

    it "resolves Claude models to :bedrock with the configured floor" do
      expect(LlmLogs::Batch.batch_provider_for("anthropic.claude-sonnet")).to eq(:bedrock)
      expect(LlmLogs::Batch.min_records_for("anthropic.claude-sonnet")).to eq(100)
    end

    it "is not batchable when the kill-switch is off" do
      allow(LlmLogs).to receive(:batch_enabled?).and_return(false)
      expect(LlmLogs::Batch.batchable?("anthropic.claude-sonnet")).to be(false)
    end
  end
end
