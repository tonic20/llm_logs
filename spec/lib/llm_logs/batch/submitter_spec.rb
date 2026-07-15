require "spec_helper"

RSpec.describe LlmLogs::Batch::Submitter do
  let(:fake_batch) do
    instance_double(
      RubyLLM::Providers::OpenAIResponses::Batch,
      id: "batch_abc",
      add: nil,
      create!: nil
    )
  end

  before do
    LlmLogs::Batch.enqueue(
      purpose: "chat_summary", model: "gpt-5.4-mini",
      input: "USER: hi", instructions: "Summarize.",
      schema: { name: "s", strict: true, schema: { type: "object" } },
      routing: { chat_id: 1 }
    )
    allow(RubyLLM).to receive(:batch).and_return(fake_batch)
    allow(LlmLogs::Batch).to receive(:servable_by_batch_provider?).with("gpt-5.4-mini").and_return(true)
  end

  it "adds each pending request, creates the batch, and persists it" do
    batch = LlmLogs::Batch.submit_pending(purpose: "chat_summary", model: "gpt-5.4-mini")

    expect(RubyLLM).to have_received(:batch).with(model: "gpt-5.4-mini", provider: :openai_responses)
    expect(fake_batch).to have_received(:add).once
    expect(fake_batch).to have_received(:add).with(
      "USER: hi",
      id: a_string_starting_with("req_"),
      instructions: "Summarize.",
      temperature: nil,
      text: { format: { type: "json_schema", name: "s", schema: { "type" => "object" }, strict: true } }
    )
    expect(fake_batch).to have_received(:create!)
    expect(batch.openai_batch_id).to eq("batch_abc")
    expect(batch.status).to eq("submitted")
    expect(batch.request_count).to eq(1)
    expect(LlmLogs::BatchRequest.first.status).to eq("submitted")
    expect(LlmLogs::BatchRequest.first.batch_id).to eq(batch.id)
  end

  it "returns nil when nothing is pending" do
    LlmLogs::BatchRequest.delete_all
    expect(LlmLogs::Batch.submit_pending(purpose: "chat_summary", model: "gpt-5.4-mini")).to be_nil
  end

  it "reverts the claim and drops the placeholder batch when submission fails" do
    allow(fake_batch).to receive(:create!).and_raise(StandardError, "openai down")

    expect {
      LlmLogs::Batch.submit_pending(purpose: "chat_summary", model: "gpt-5.4-mini")
    }.to raise_error(StandardError, "openai down")

    request = LlmLogs::BatchRequest.first
    expect(request.status).to eq("pending")
    expect(request.batch_id).to be_nil
    expect(LlmLogs::Batch.count).to eq(0)
  end

  context "with a Bedrock model" do
    let(:fake_bedrock_adapter) { double("bedrock_adapter") }

    before do
      LlmLogs.configuration.bedrock_batch = LlmLogs::Configuration::BedrockBatch.new(
        role_arn: "arn", s3_bucket: "b", s3_prefix: "p", min_records: 1,
        model_matcher: /\Aanthropic\./, region: "us-east-1"
      )
      LlmLogs.register_batch_adapter(:bedrock, fake_bedrock_adapter)
      allow(fake_bedrock_adapter).to receive(:submit).and_return(
        provider_batch_id: "arn:job", openai_batch_id: nil, provider_metadata: {}
      )

      LlmLogs::Batch.enqueue(
        purpose: "eval_judge", model: "anthropic.claude-sonnet",
        input: "USER: hi", instructions: "Judge.",
        schema: { name: "s", strict: true, schema: { type: "object" } },
        routing: { chat_id: 1 }
      )
    end

    after do
      LlmLogs.configuration.bedrock_batch = nil
      LlmLogs.batch_adapters.delete(:bedrock)
    end

    it "routes to the Bedrock adapter and records provider: bedrock on the batch" do
      batch = LlmLogs::Batch.submit_pending(purpose: "eval_judge", model: "anthropic.claude-sonnet")

      expect(fake_bedrock_adapter).to have_received(:submit).with(batch, instance_of(Array))
      expect(RubyLLM).not_to have_received(:batch)
      expect(batch.provider).to eq("bedrock")
      expect(batch.provider_batch_id).to eq("arn:job")
      expect(batch.status).to eq("submitted")
    end
  end
end
