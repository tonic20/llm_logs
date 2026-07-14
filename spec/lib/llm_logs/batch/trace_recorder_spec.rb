require "spec_helper"

RSpec.describe LlmLogs::Batch::TraceRecorder do
  let(:request) do
    LlmLogs::BatchRequest.create!(
      custom_id: "req_1", purpose: "chat_summary", model: "gpt-5.4-mini",
      payload: { "input" => "USER: hi", "instructions" => "Summarize." }
    )
  end

  let(:message) do
    instance_double(RubyLLM::Message, content: "the summary", input_tokens: 100, output_tokens: 20, model_id: "gpt-5.4-mini")
  end

  it "creates a completed trace with an llm span carrying tokens" do
    request.update!(routing: { "chat_id" => 7, "execution_mode" => "spoofed" })
    trace = described_class.record(request: request, message: message, provider: "openai_responses")

    expect(trace).to be_a(LlmLogs::Trace)
    expect(trace.name).to eq("chat_summary")
    expect(trace.status).to eq("completed")
    expect(trace.metadata).to include("chat_id" => 7, "execution_mode" => "batch")
    expect(trace.total_input_tokens).to eq(100)
    expect(trace.total_output_tokens).to eq(20)
    span = trace.spans.first
    expect(span.span_type).to eq("llm")
    expect(span.model).to eq("gpt-5.4-mini")
    expect(span.provider).to eq("openai_responses")
    expect(span.output).to eq({ "content" => "the summary" })
  end

  it "links the trace to a prompt_version_id from routing when present" do
    request.update!(routing: { "prompt_version_id" => nil })
    trace = described_class.record(request: request, message: message, provider: "openai_responses")
    expect(trace.prompt_version_id).to be_nil
  end
end
