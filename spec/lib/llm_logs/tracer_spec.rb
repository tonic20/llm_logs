require "spec_helper"

RSpec.describe LlmLogs::Tracer do
  after do
    Thread.current[:llm_logs_trace] = nil
    Thread.current[:llm_logs_span] = nil
  end

  describe ".start_trace" do
    it "creates a trace and yields it" do
      LlmLogs::Tracer.start_trace("test_trace") do |trace|
        expect(trace).to be_a(LlmLogs::Trace)
        expect(trace.name).to eq("test_trace")
        expect(trace.status).to eq("running")
        expect(LlmLogs::Tracer.current_trace).to eq(trace)
      end
    end

    it "completes the trace after the block" do
      trace = nil
      LlmLogs::Tracer.start_trace("test") { |t| trace = t }

      expect(trace.reload.status).to eq("completed")
      expect(trace.completed_at).to be_present
    end

    it "marks trace as errored on exception" do
      trace = nil
      expect {
        LlmLogs::Tracer.start_trace("test") do |t|
          trace = t
          raise "boom"
        end
      }.to raise_error("boom")

      expect(trace.reload.status).to eq("errored")
    end

    it "restores previous trace context" do
      outer_trace = nil
      LlmLogs::Tracer.start_trace("outer") do |ot|
        outer_trace = ot
        LlmLogs::Tracer.start_trace("inner") do |_it|
          expect(LlmLogs::Tracer.current_trace).not_to eq(outer_trace)
        end
        expect(LlmLogs::Tracer.current_trace).to eq(outer_trace)
      end
    end

    it "uses default_project when project not specified" do
      LlmLogs.default_project = "myapp"
      LlmLogs::Tracer.start_trace("test") do |trace|
        expect(trace.project).to eq("myapp")
      end
    ensure
      LlmLogs.default_project = "default"
    end
  end

  describe ".start_span" do
    it "creates a span under the current trace" do
      LlmLogs::Tracer.start_trace("test") do |trace|
        span = LlmLogs::Tracer.start_span(name: "chat.complete", span_type: "llm", model: "gpt-4")

        expect(span.trace).to eq(trace)
        expect(span.name).to eq("chat.complete")
        expect(span.model).to eq("gpt-4")
      end
    end

    it "auto-creates a trace when none is active" do
      span = LlmLogs::Tracer.start_span(name: "chat.complete", span_type: "llm")

      expect(span.trace).to be_present
      expect(span.trace.name).to eq("auto:chat.complete")

      # Clean up auto-created trace
      span.trace.complete!
    end

    it "nests spans with parent references" do
      LlmLogs::Tracer.start_trace("test") do |_trace|
        parent = LlmLogs::Tracer.start_span(name: "chat.complete", span_type: "llm")
        child = LlmLogs::Tracer.start_span(name: "tool.search", span_type: "tool")

        expect(child.parent_span).to eq(parent)
      end
    end
  end
end
