require "spec_helper"

RSpec.describe LlmLogs::PurgeJob do
  around do |example|
    original = LlmLogs.retention_days
    example.run
  ensure
    LlmLogs.retention_days = original
  end

  def trace_with_spans(started_at)
    trace = LlmLogs::Trace.create!(name: "turn", status: "completed", started_at: started_at)
    round = LlmLogs::Span.create!(trace: trace, name: "chat.complete", span_type: "llm", started_at: started_at)
    LlmLogs::Span.create!(trace: trace, name: "tool.weather", span_type: "tool", started_at: started_at, parent_span: round)
    trace
  end

  it "deletes traces started before the retention window, with their spans" do
    LlmLogs.retention_days = 30
    old = trace_with_spans(31.days.ago)
    recent = trace_with_spans(29.days.ago)

    described_class.perform_now

    expect(LlmLogs::Trace.where(id: old.id)).to be_empty
    expect(LlmLogs::Span.where(trace_id: old.id)).to be_empty
    expect(LlmLogs::Trace.where(id: recent.id)).to exist
    expect(LlmLogs::Span.where(trace_id: recent.id).count).to eq(2)
  end

  it "unlinks batch requests from the traces it deletes" do
    LlmLogs.retention_days = 30
    old = trace_with_spans(31.days.ago)
    batch = LlmLogs::Batch.create!(purpose: "eval_judge", model: "gpt-5.4-mini")
    request = LlmLogs::BatchRequest.create!(batch: batch, custom_id: "req_1", purpose: "eval_judge",
                                            model: "gpt-5.4-mini", status: "succeeded", trace_id: old.id)

    described_class.perform_now

    expect(request.reload.trace_id).to be_nil
  end

  it "keeps everything when retention_days is nil" do
    LlmLogs.retention_days = nil
    old = trace_with_spans(5.years.ago)

    described_class.perform_now

    expect(LlmLogs::Trace.where(id: old.id)).to exist
  end
end
