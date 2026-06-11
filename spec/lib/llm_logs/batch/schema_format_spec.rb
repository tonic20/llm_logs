require "spec_helper"

RSpec.describe LlmLogs::Batch::SchemaFormat do
  it "wraps a {name, schema, strict} schema into Responses text.format" do
    schema = { name: "chat_summary", strict: true, schema: { type: "object" } }
    result = described_class.call(schema)
    expect(result).to eq(
      format: {
        type: "json_schema",
        name: "chat_summary",
        schema: { type: "object" },
        strict: true
      }
    )
  end

  it "defaults name to 'response' and strict to true" do
    result = described_class.call({ schema: { type: "object" } })
    expect(result[:format][:name]).to eq("response")
    expect(result[:format][:strict]).to be(true)
  end

  it "returns nil for a nil schema" do
    expect(described_class.call(nil)).to be_nil
  end
end
