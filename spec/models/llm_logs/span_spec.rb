require "spec_helper"

RSpec.describe LlmLogs::Span do
  let(:trace) { LlmLogs::Trace.create!(name: "test", started_at: Time.current, status: "running") }

  describe "validations" do
    it "requires name, span_type, and started_at" do
      span = LlmLogs::Span.new(trace: trace)
      expect(span).not_to be_valid
      expect(span.errors[:name]).to include("can't be blank")
      expect(span.errors[:span_type]).to include("can't be blank")
      expect(span.errors[:started_at]).to include("can't be blank")
    end

    it "validates span_type inclusion" do
      span = LlmLogs::Span.new(trace: trace, name: "test", span_type: "invalid", started_at: Time.current)
      expect(span).not_to be_valid
    end

    it "is valid with required attributes" do
      span = LlmLogs::Span.new(trace: trace, name: "test", span_type: "llm", started_at: Time.current)
      expect(span).to be_valid
    end
  end

  describe "associations" do
    it "supports parent-child span hierarchy" do
      parent = LlmLogs::Span.create!(trace: trace, name: "parent", span_type: "llm", started_at: Time.current)
      child = LlmLogs::Span.create!(trace: trace, name: "child", span_type: "tool", started_at: Time.current, parent_span: parent)

      expect(parent.child_spans).to eq([child])
      expect(child.parent_span).to eq(parent)
    end
  end

  describe "#finish" do
    it "sets completed_at and duration_ms" do
      span = LlmLogs::Span.create!(trace: trace, name: "test", span_type: "llm", started_at: 1.second.ago)
      Thread.current[:llm_logs_span] = span

      span.finish

      expect(span.completed_at).to be_present
      expect(span.duration_ms).to be > 0
    end

    it "restores parent span as current" do
      parent = LlmLogs::Span.create!(trace: trace, name: "parent", span_type: "llm", started_at: Time.current)
      child = LlmLogs::Span.create!(trace: trace, name: "child", span_type: "tool", started_at: Time.current, parent_span: parent)
      Thread.current[:llm_logs_span] = child

      child.finish

      expect(Thread.current[:llm_logs_span]).to eq(parent)
    end
  end

  describe "#record_error" do
    it "sets status to error with message" do
      span = LlmLogs::Span.create!(trace: trace, name: "test", span_type: "llm", started_at: Time.current)
      span.record_error(RuntimeError.new("something broke"))

      expect(span.status).to eq("error")
      expect(span.error_message).to eq("RuntimeError: something broke")
    end
  end

  describe "#set_attribute" do
    it "merges into metadata" do
      span = LlmLogs::Span.create!(trace: trace, name: "test", span_type: "llm", started_at: Time.current)
      span.set_attribute("foo", "bar")
      span.set_attribute("baz", 42)

      expect(span.metadata).to eq("foo" => "bar", "baz" => 42)
    end
  end
end
