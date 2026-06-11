require "spec_helper"

RSpec.describe "LlmLogs::Batch.enqueue" do
  it "creates a pending request carrying payload and routing" do
    request = LlmLogs::Batch.enqueue(
      purpose: "chat_summary",
      model: "gpt-5.4-mini",
      input: "USER: hi",
      instructions: "Summarize.",
      schema: { name: "s", strict: true, schema: { type: "object" } },
      routing: { chat_id: 42 }
    )

    expect(request).to be_persisted
    expect(request.status).to eq("pending")
    expect(request.batch_id).to be_nil
    expect(request.payload["input"]).to eq("USER: hi")
    expect(request.payload["instructions"]).to eq("Summarize.")
    expect(request.routing["chat_id"]).to eq(42)
    expect(request.custom_id).to start_with("req_")
  end

  it "batchable? is false when batching disabled" do
    LlmLogs.configuration.batch_enabled = false
    expect(LlmLogs::Batch.batchable?("gpt-5.4-mini")).to be(false)
  ensure
    LlmLogs.configuration.batch_enabled = true
  end
end
