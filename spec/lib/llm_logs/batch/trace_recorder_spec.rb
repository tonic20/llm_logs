require "spec_helper"

RSpec.describe LlmLogs::Batch::TraceRecorder do
  let(:model) { "us.anthropic.claude-haiku-4-5-20251001-v1:0" }
  let(:request) do
    LlmLogs::BatchRequest.create!(
      custom_id: "req_1", purpose: "chat_summary", model: model,
      payload: { "input" => "USER: hi", "instructions" => "Summarize." }
    )
  end

  # Bedrock batch output reports the native Anthropic id, not the Bedrock one.
  let(:message) do
    LlmLogs::Batch::Adapters::Bedrock::Result.new(content: "the summary", input_tokens: 100, output_tokens: 20,
                                                  model_id: "claude-haiku-4-5-20251001")
  end

  it "creates a completed trace with an llm span carrying tokens" do
    request.update!(routing: { "chat_id" => 7, "execution_mode" => "spoofed" })
    trace = described_class.record(request: request, message: message, provider: "bedrock")

    expect(trace).to be_a(LlmLogs::Trace)
    expect(trace.name).to eq("chat_summary")
    expect(trace.status).to eq("completed")
    expect(trace.metadata).to include("chat_id" => 7, "execution_mode" => "batch")
    expect(trace.total_input_tokens).to eq(100)
    expect(trace.total_output_tokens).to eq(20)
    span = trace.spans.first
    expect(span.span_type).to eq("llm")
    expect(span.model).to eq("claude-haiku-4-5-20251001")
    expect(span.provider).to eq("bedrock")
    expect(span.output).to eq({ "content" => "the summary" })
  end

  it "prices the submitted Bedrock model at half its standard rate" do
    trace = described_class.record(request: request, message: message, provider: "bedrock")

    # us. Haiku 4.5 on Bedrock: 1.1 in / 5.5 out per million
    expect(trace.total_cost.to_f).to be_within(1e-9).of((100 * 1.1 + 20 * 5.5) / 1e6 * 0.5)
  end

  it "falls back to the reported model id when the submitted one is unknown" do
    request.update!(model: "us.anthropic.not-a-model")
    trace = described_class.record(request: request, message: message, provider: "bedrock")

    # claude-haiku-4-5-20251001 resolves to the anthropic provider: 1.0 in / 5.0 out
    expect(trace.total_cost.to_f).to be_within(1e-9).of((100 * 1.0 + 20 * 5.0) / 1e6 * 0.5)
  end

  it "leaves the cost empty for a model without registry pricing" do
    request.update!(model: "us.openai.gpt-6-sol")
    unpriced = message.dup.tap { |m| m.model_id = "us.openai.gpt-6-sol" }

    expect(described_class.record(request: request, message: unpriced, provider: "bedrock").spans.first.cost).to be_nil
  end

  it "links the trace to a prompt_version_id from routing when present" do
    request.update!(routing: { "prompt_version_id" => nil })
    trace = described_class.record(request: request, message: message, provider: "bedrock")
    expect(trace.prompt_version_id).to be_nil
  end
end
