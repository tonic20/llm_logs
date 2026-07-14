require "spec_helper"

RSpec.describe LlmLogs::Batch::Adapters::OpenaiResponses do
  let(:adapter) { described_class.new }
  let(:batch) { LlmLogs::Batch.create!(purpose: "chat_summary", model: "gpt-5.4-mini", status: "pending", provider: "openai_responses") }
  let(:request) do
    batch.requests.create!(custom_id: "req_1", purpose: "chat_summary", model: "gpt-5.4-mini", status: "submitted",
                           payload: {"input" => "USER: hi", "instructions" => "Summarize.", "schema" => {"name" => "s", "strict" => true, "schema" => {"type" => "object"}}})
  end
  let(:rubyllm_batch) { instance_double(RubyLLM::Providers::OpenAIResponses::Batch, id: "batch_abc", add: nil, create!: nil) }

  it "submits each request and returns the provider batch id" do
    allow(RubyLLM).to receive(:batch).with(model: "gpt-5.4-mini", provider: :openai_responses).and_return(rubyllm_batch)
    request # create it
    result = adapter.submit(batch, batch.requests.to_a)
    expect(rubyllm_batch).to have_received(:add).with(
      "USER: hi", id: "req_1", instructions: "Summarize.", temperature: nil,
      text: {format: {type: "json_schema", name: "s", schema: {"type" => "object"}, strict: true}}
    )
    expect(rubyllm_batch).to have_received(:create!)
    expect(result).to eq(provider_batch_id: "batch_abc", openai_batch_id: "batch_abc", provider_metadata: {})
  end

  it "reads status, results, and error ids by provider_batch_id" do
    batch.update!(provider_batch_id: "batch_abc")
    resumed = instance_double(RubyLLM::Providers::OpenAIResponses::Batch,
                              status: "completed", results: {"req_1" => :msg}, errors: [{"custom_id" => "req_2"}])
    allow(RubyLLM).to receive(:batch).with(id: "batch_abc", provider: :openai_responses).and_return(resumed)
    expect(adapter.terminal_status(batch)).to eq("completed")
    expect(adapter.results(batch)).to eq("req_1" => :msg)
    expect(adapter.error_ids(batch)).to eq(["req_2"])
  end
end
