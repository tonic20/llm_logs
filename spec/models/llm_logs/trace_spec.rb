require "spec_helper"

RSpec.describe LlmLogs::Trace do
  describe "validations" do
    it "requires a name" do
      trace = LlmLogs::Trace.new(started_at: Time.current)
      expect(trace).not_to be_valid
      expect(trace.errors[:name]).to include("can't be blank")
    end

    it "requires started_at" do
      trace = LlmLogs::Trace.new(name: "test")
      expect(trace).not_to be_valid
      expect(trace.errors[:started_at]).to include("can't be blank")
    end

    it "validates status inclusion" do
      trace = LlmLogs::Trace.new(name: "test", started_at: Time.current, status: "invalid")
      expect(trace).not_to be_valid
      expect(trace.errors[:status]).to be_present
    end

    it "is valid with required attributes" do
      trace = LlmLogs::Trace.new(name: "test", started_at: Time.current, status: "running")
      expect(trace).to be_valid
    end
  end

  describe "#complete!" do
    it "sets status to completed with timestamp and duration" do
      trace = LlmLogs::Trace.create!(name: "test", started_at: 1.second.ago, status: "running")
      trace.complete!

      expect(trace.status).to eq("completed")
      expect(trace.completed_at).to be_present
      expect(trace.duration_ms).to be > 0
    end

    it "rolls up token counts from spans" do
      trace = LlmLogs::Trace.create!(name: "test", started_at: Time.current, status: "running")
      LlmLogs::Span.create!(
        trace: trace, name: "span1", span_type: "llm",
        started_at: Time.current, input_tokens: 100, output_tokens: 50, cost: 0.001
      )
      LlmLogs::Span.create!(
        trace: trace, name: "span2", span_type: "llm",
        started_at: Time.current, input_tokens: 200, output_tokens: 75, cost: 0.002
      )

      trace.complete!

      expect(trace.total_input_tokens).to eq(300)
      expect(trace.total_output_tokens).to eq(125)
      expect(trace.total_cost).to eq(0.003)
    end

    it "is idempotent" do
      trace = LlmLogs::Trace.create!(name: "test", started_at: Time.current, status: "running")
      trace.complete!
      completed_at = trace.completed_at
      trace.complete!
      expect(trace.completed_at).to eq(completed_at)
    end
  end

  describe "#root_spans" do
    it "returns only top-level spans" do
      trace = LlmLogs::Trace.create!(name: "test", started_at: Time.current, status: "running")
      root = LlmLogs::Span.create!(trace: trace, name: "root", span_type: "llm", started_at: Time.current)
      _child = LlmLogs::Span.create!(trace: trace, name: "child", span_type: "tool", started_at: Time.current, parent_span: root)

      expect(trace.root_spans).to eq([root])
    end
  end

  describe "#prompt_version" do
    it "can reference a prompt version" do
      prompt = LlmLogs::Prompt.create!(slug: "test", name: "Test")
      prompt.update_content!(messages: [{ "role" => "user", "content" => "Hello" }])
      version = prompt.current_version

      trace = LlmLogs::Trace.create!(
        name: "test", started_at: Time.current, status: "running",
        prompt_version: version
      )

      expect(trace.prompt_version).to eq(version)
    end

    it "is optional" do
      trace = LlmLogs::Trace.create!(name: "test", started_at: Time.current, status: "running")
      expect(trace.prompt_version).to be_nil
    end
  end

  describe "scopes" do
    it ".recent orders by started_at desc" do
      old = LlmLogs::Trace.create!(name: "old", started_at: 2.hours.ago, status: "completed")
      new_trace = LlmLogs::Trace.create!(name: "new", started_at: 1.minute.ago, status: "running")

      expect(LlmLogs::Trace.recent.first).to eq(new_trace)
    end

    it ".by_status filters by status" do
      t1 = LlmLogs::Trace.create!(name: "t1", status: "completed", started_at: Time.current)
      _t2 = LlmLogs::Trace.create!(name: "t2", status: "running", started_at: Time.current)

      expect(LlmLogs::Trace.by_status("completed")).to eq([t1])
    end
  end
end
