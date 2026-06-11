require "spec_helper"

RSpec.describe LlmLogs::Batch::FlushJob do
  it "submits pending requests grouped by model for the purpose" do
    LlmLogs::Batch.enqueue(purpose: "chat_summary", model: "gpt-5.4-mini", input: "a",
                           instructions: "x", schema: nil, routing: {})
    LlmLogs::Batch.enqueue(purpose: "chat_summary", model: "gpt-5.4-mini", input: "b",
                           instructions: "x", schema: nil, routing: {})

    expect(LlmLogs::Batch).to receive(:submit_pending).with(purpose: "chat_summary", model: "gpt-5.4-mini")

    LlmLogs::Batch::FlushJob.new.perform("chat_summary")
  end
end
