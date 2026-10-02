require "spec_helper"

RSpec.describe "LlmLogs::Batch.enqueue", :postgresql do
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

  it "carries reasoning_effort into the payload when given" do
    request = LlmLogs::Batch.enqueue(
      purpose: "chat_summary", model: "gpt-5.6-luna", input: "USER: hi",
      instructions: "Summarize.", schema: nil, routing: {}, reasoning_effort: "low"
    )

    expect(request.payload["reasoning_effort"]).to eq("low")
  end

  it "omits reasoning_effort from the payload when not given" do
    request = LlmLogs::Batch.enqueue(
      purpose: "chat_summary", model: "gpt-5.6-luna", input: "USER: hi",
      instructions: "Summarize.", schema: nil, routing: {}
    )

    expect(request.payload).not_to have_key("reasoning_effort")
  end

  it "batchable? is false when batching disabled" do
    LlmLogs.configuration.batch_enabled = false
    expect(LlmLogs::Batch.batchable?("gpt-5.4-mini")).to be(false)
  ensure
    LlmLogs.configuration.batch_enabled = true
  end

  it "batchable? is false when no batch adapter serves the model" do
    expect(LlmLogs::Batch.batchable?("us.openai.gpt-6-sol")).to be(false)
  end
end
