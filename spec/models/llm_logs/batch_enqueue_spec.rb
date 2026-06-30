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

  it "batchable? is true when the batch provider can serve the model" do
    allow(RubyLLM::Models).to receive(:resolve).and_return([double("model"), double("provider")])

    expect(LlmLogs::Batch.batchable?("gpt-5.4-mini")).to be(true)
    expect(RubyLLM::Models).to have_received(:resolve)
      .with("gpt-5.4-mini", hash_including(provider: LlmLogs.batch_provider, assume_exists: false))
  end

  it "batchable? is false when the model is not servable by the batch provider (e.g. Bedrock/Anthropic)" do
    allow(RubyLLM::Models).to receive(:resolve).and_raise(RubyLLM::ModelNotFoundError)

    expect(LlmLogs::Batch.batchable?("anthropic.claude-haiku-4-5")).to be(false)
  end
end
