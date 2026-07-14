require "spec_helper"

RSpec.describe LlmLogs::Batch::PollJob do
  it "reconciles every unreconciled batch that has an openai_batch_id" do
    b1 = LlmLogs::Batch.create!(purpose: "chat_summary", model: "m", status: "submitted", openai_batch_id: "b1", provider_batch_id: "b1")
    LlmLogs::Batch.create!(purpose: "chat_summary", model: "m", status: "reconciled", openai_batch_id: "b2", provider_batch_id: "b2")
    LlmLogs::Batch.create!(purpose: "chat_summary", model: "m", status: "pending", openai_batch_id: nil, provider_batch_id: nil)

    reconciled = []
    allow_any_instance_of(LlmLogs::Batch::Reconciler).to receive(:call) { |recon| reconciled << recon.instance_variable_get(:@batch).id }

    LlmLogs::Batch::PollJob.new.perform

    expect(reconciled).to eq([b1.id])
  end

  it "recovers stale placeholder claims by reverting requests to pending and dropping the batch" do
    stale = LlmLogs::Batch.create!(purpose: "chat_summary", model: "m", status: "pending",
                                   openai_batch_id: nil, provider_batch_id: nil, created_at: 1.hour.ago)
    req = stale.requests.create!(custom_id: "req_stale", purpose: "chat_summary", model: "m", status: "submitted")

    LlmLogs::Batch::PollJob.new.perform

    expect(LlmLogs::Batch.exists?(stale.id)).to be(false)
    expect(req.reload.status).to eq("pending")
    expect(req.batch_id).to be_nil
  end

  it "does not recover a fresh placeholder claim" do
    fresh = LlmLogs::Batch.create!(purpose: "chat_summary", model: "m", status: "pending", openai_batch_id: nil, provider_batch_id: nil)
    LlmLogs::Batch::PollJob.new.perform
    expect(LlmLogs::Batch.exists?(fresh.id)).to be(true)
  end
end
