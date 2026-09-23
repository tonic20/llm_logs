require "spec_helper"

RSpec.describe "SQLite prompt and batch compatibility" do
  it "matches exact case-sensitive tags safely, including quotes and duplicates" do
    wanted = LlmLogs::Prompt.create!(slug: "one", name: "One", tags: ["Racing", "driver's", "Racing"])
    other = LlmLogs::Prompt.create!(slug: "two", name: "Two", tags: ["racing"])
    expect(LlmLogs::Prompt.with_tag("Racing").pluck(:id)).to eq([wanted.id])
    expect(LlmLogs::Prompt.with_tag("racing").pluck(:id)).to eq([other.id])
    expect(LlmLogs::Prompt.with_any_tag(["driver's", "missing"]).pluck(:id)).to eq([wanted.id])
    expect(LlmLogs::Prompt.with_any_tag([])).to be_empty
    expect(LlmLogs::Prompt.with_tag("' OR 1=1 --")).to be_empty
  end

  context "on SQLite", if: ENV["LLM_LOGS_DATABASE"] == "sqlite" do
    it "reports batch capability unavailable" do
      expect(LlmLogs::Batch.supported_adapter?).to be(false)
      expect(LlmLogs::Batch.batchable?("gpt-4.1")).to be(false)
    end

    it "guards direct enqueue, submit, reconcile and jobs without state changes" do
      batch = LlmLogs::Batch.create!(purpose: "test", model: "gpt-4.1")
      operations = [
        -> { LlmLogs::Batch.enqueue(purpose: "test", model: "gpt-4.1", input: "a", instructions: "b", schema: {}, routing: {}) },
        -> { LlmLogs::Batch::Submitter.new(purpose: "test", model: "gpt-4.1").call },
        -> { LlmLogs::Batch::Reconciler.new(batch).call },
        -> { LlmLogs::Batch::FlushJob.perform_now("test") },
        -> { LlmLogs::Batch::PollJob.perform_now }
      ]
      operations.each do |operation|
        expect { operation.call }.to raise_error(LlmLogs::Batch::UnsupportedAdapter, /PostgreSQL/)
      end
      expect(batch.reload.status).to eq("pending")
      expect(LlmLogs::BatchRequest.count).to eq(0)
    end
  end
end
