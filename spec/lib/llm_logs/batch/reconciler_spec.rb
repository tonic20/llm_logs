require "spec_helper"

RSpec.describe LlmLogs::Batch::Reconciler, :postgresql do
  let(:handler) { double("handler") }
  let(:model) { "us.anthropic.claude-haiku-4-5-20251001-v1:0" }
  let(:message) do
    LlmLogs::Batch::Adapters::Bedrock::Result.new(content: "summary", input_tokens: 1000, output_tokens: 500, model_id: model)
  end
  let(:adapter) { double("bedrock_adapter", terminal_status: "completed", results: {"req_1" => message}, error_ids: []) }

  let!(:batch) do
    LlmLogs::Batch.create!(purpose: "chat_summary", model: model, provider: "bedrock", status: "submitted",
                           provider_batch_id: "arn:job", request_count: 1)
  end
  let!(:request) do
    batch.requests.create!(custom_id: "req_1", purpose: "chat_summary", model: model, status: "submitted",
                           payload: { "input" => "USER: hi" }, routing: { "chat_id" => 7 })
  end

  before do
    LlmLogs.register_batch_handler("chat_summary", handler)
    LlmLogs.register_batch_adapter(:bedrock, adapter)
  end

  after do
    LlmLogs::Batch::HandlerRegistry.clear!
    LlmLogs.batch_adapters.delete(:bedrock)
  end

  it "records the trace, marks the request succeeded, and invokes the handler" do
    expect(handler).to receive(:call).with(request, message)
    expect_any_instance_of(LlmLogs::BatchRequest).to receive(:succeeded!).and_call_original

    described_class.new(batch).call

    request.reload
    expect(request.status).to eq("succeeded")
    expect(request.input_tokens).to eq(1000)
    expect(request.trace_id).to be_present
    expect(request.cost.to_f).to be_within(1e-9).of((1000 * 1.1 + 500 * 5.5) / 1e6 * 0.5)
    expect(batch.reload.status).to eq("reconciled")
  end

  it "does nothing while the batch is still in progress" do
    allow(adapter).to receive(:terminal_status).and_return("in_progress")

    described_class.new(batch).call
    expect(batch.reload.status).to eq("submitted")
    expect(request.reload.status).to eq("submitted")
  end

  it "marks the request failed (not succeeded) when the success handler raises" do
    allow(handler).to receive(:call).and_raise(StandardError, "boom")

    described_class.new(batch).call

    request.reload
    expect(request.status).to eq("failed")
    expect(request.error).to include("handler error").and include("boom")
    expect(request.trace_id).to be_present  # trace still recorded; spend happened
    expect(batch.reload.status).to eq("reconciled")
  end

  it "fails all open requests and invokes on_failure when the batch failed" do
    expect(adapter).to receive(:terminal_status).once.and_return("failed")
    allow(handler).to receive(:on_failure)

    described_class.new(batch).call

    expect(request.reload.status).to eq("failed")
    expect(request.error).to include("batch failed")
    expect(handler).to have_received(:on_failure).with(request, a_string_including("batch failed"))
    expect(batch.reload.status).to eq("failed")
  end

  it "fails a request with no result for its custom_id and invokes on_failure" do
    allow(adapter).to receive(:results).and_return({})
    allow(handler).to receive(:on_failure)

    described_class.new(batch).call

    expect(request.reload.status).to eq("failed")
    expect(request.error).to include("no result for custom_id")
    expect(handler).to have_received(:on_failure).with(request, a_string_including("no result for custom_id"))
    expect(batch.reload.status).to eq("reconciled")
  end
end
