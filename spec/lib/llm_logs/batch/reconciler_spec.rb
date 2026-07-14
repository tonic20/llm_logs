require "spec_helper"

RSpec.describe LlmLogs::Batch::Reconciler do
  let(:handler) { double("handler") }
  let(:message) { instance_double(RubyLLM::Message, content: "summary", input_tokens: 10, output_tokens: 5, model_id: "gpt-5.4-mini") }

  let!(:batch) do
    LlmLogs::Batch.create!(purpose: "chat_summary", model: "gpt-5.4-mini", status: "submitted",
                           openai_batch_id: "batch_abc", provider_batch_id: "batch_abc", request_count: 1)
  end
  let!(:request) do
    batch.requests.create!(custom_id: "req_1", purpose: "chat_summary", model: "gpt-5.4-mini", status: "submitted",
                           payload: { "input" => "USER: hi" }, routing: { "chat_id" => 7 })
  end

  let(:rubyllm_batch) { instance_double(RubyLLM::Providers::OpenAIResponses::Batch) }

  before do
    LlmLogs.register_batch_handler("chat_summary", handler)
    allow(RubyLLM).to receive(:batch).with(id: "batch_abc", provider: :openai_responses).and_return(rubyllm_batch)
    allow(rubyllm_batch).to receive(:status).and_return("completed")
    allow(rubyllm_batch).to receive(:completed?).and_return(true)
    allow(rubyllm_batch).to receive(:results).and_return({ "req_1" => message })
    allow(rubyllm_batch).to receive(:errors).and_return([])
  end

  after { LlmLogs::Batch::HandlerRegistry.clear! }

  it "records the trace, marks the request succeeded, and invokes the handler" do
    expect(handler).to receive(:call).with(request, message)
    expect_any_instance_of(LlmLogs::BatchRequest).to receive(:succeeded!).and_call_original

    described_class.new(batch).call

    request.reload
    expect(request.status).to eq("succeeded")
    expect(request.input_tokens).to eq(10)
    expect(request.trace_id).to be_present
    expect(batch.reload.status).to eq("reconciled")
  end

  it "does nothing while the batch is still in progress" do
    allow(rubyllm_batch).to receive(:status).and_return("in_progress")
    allow(rubyllm_batch).to receive(:completed?).and_return(false)

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
    expect(rubyllm_batch).to receive(:status).once.and_return("failed")
    allow(handler).to receive(:on_failure)

    described_class.new(batch).call

    expect(request.reload.status).to eq("failed")
    expect(request.error).to include("batch failed")
    expect(handler).to have_received(:on_failure).with(request, a_string_including("batch failed"))
    expect(batch.reload.status).to eq("failed")
  end

  it "fails a request with no result for its custom_id and invokes on_failure" do
    allow(rubyllm_batch).to receive(:results).and_return({})
    allow(handler).to receive(:on_failure)

    described_class.new(batch).call

    expect(request.reload.status).to eq("failed")
    expect(request.error).to include("no result for custom_id")
    expect(handler).to have_received(:on_failure).with(request, a_string_including("no result for custom_id"))
    expect(batch.reload.status).to eq("reconciled")
  end
end
