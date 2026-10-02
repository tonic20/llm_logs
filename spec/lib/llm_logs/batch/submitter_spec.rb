require "spec_helper"

RSpec.describe LlmLogs::Batch::Submitter, :postgresql do
  let(:adapter) { double("bedrock_adapter") }
  let(:model) { "anthropic.claude-sonnet" }

  before do
    LlmLogs.configuration.bedrock_batch = LlmLogs::Configuration::BedrockBatch.new(
      role_arn: "arn", s3_bucket: "b", s3_prefix: "p", min_records: 1,
      model_matcher: /\Aanthropic\./, region: "us-east-1"
    )
    LlmLogs.register_batch_adapter(:bedrock, adapter)
    allow(adapter).to receive(:submit).and_return(
      provider_batch_id: "arn:job", openai_batch_id: nil, provider_metadata: {"job_id" => "job"}
    )

    LlmLogs::Batch.enqueue(
      purpose: "eval_judge", model: model,
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
    batch = LlmLogs::Batch.submit_pending(purpose: "eval_judge", model: model)

    expect(adapter).to have_received(:submit).with(batch, instance_of(Array))
    expect(batch.provider).to eq("bedrock")
    expect(batch.provider_batch_id).to eq("arn:job")
    expect(batch.provider_metadata).to eq("job_id" => "job")
    expect(batch.status).to eq("submitted")
    expect(batch.request_count).to eq(1)
    expect(LlmLogs::BatchRequest.first.status).to eq("submitted")
    expect(LlmLogs::BatchRequest.first.batch_id).to eq(batch.id)
  end

  it "returns nil when nothing is pending" do
    LlmLogs::BatchRequest.delete_all
    expect(LlmLogs::Batch.submit_pending(purpose: "eval_judge", model: model)).to be_nil
  end

  it "reverts the claim and drops the placeholder batch when submission fails" do
    allow(adapter).to receive(:submit).and_raise(StandardError, "bedrock down")

    expect {
      LlmLogs::Batch.submit_pending(purpose: "eval_judge", model: model)
    }.to raise_error(StandardError, "bedrock down")

    request = LlmLogs::BatchRequest.first
    expect(request.status).to eq("pending")
    expect(request.batch_id).to be_nil
    expect(LlmLogs::Batch.count).to eq(0)
  end
end
