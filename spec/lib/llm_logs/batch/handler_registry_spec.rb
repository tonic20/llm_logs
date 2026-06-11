require "spec_helper"

RSpec.describe "LlmLogs batch handler registry" do
  after { LlmLogs::Batch::HandlerRegistry.clear! }

  it "registers and resolves a handler by purpose" do
    handler = Object.new
    LlmLogs.register_batch_handler("chat_summary", handler)
    expect(LlmLogs.batch_handler("chat_summary")).to eq(handler)
  end

  it "returns nil for an unknown purpose" do
    expect(LlmLogs.batch_handler("nope")).to be_nil
  end
end
