require "spec_helper"

RSpec.describe LlmLogs::BatchRequest do
  it "requires custom_id, purpose, and model" do
    request = LlmLogs::BatchRequest.new
    expect(request).not_to be_valid
    expect(request.errors.attribute_names).to include(:custom_id, :purpose, :model)
  end

  it "enforces unique custom_id" do
    LlmLogs::BatchRequest.create!(custom_id: "req_dup", purpose: "chat_summary", model: "m")
    dup = LlmLogs::BatchRequest.new(custom_id: "req_dup", purpose: "chat_summary", model: "m")
    expect(dup).not_to be_valid
  end
end
