require "spec_helper"

RSpec.describe LlmLogs::Batch do
  it "requires purpose and model" do
    batch = LlmLogs::Batch.new
    expect(batch).not_to be_valid
    expect(batch.errors.attribute_names).to include(:purpose, :model)
  end

  it "has many requests" do
    batch = LlmLogs::Batch.create!(purpose: "chat_summary", model: "gpt-5.4-mini", status: "pending")
    batch.requests.create!(custom_id: "req_1", purpose: "chat_summary", model: "gpt-5.4-mini")
    expect(batch.requests.count).to eq(1)
  end
end
