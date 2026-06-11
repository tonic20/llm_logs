module LlmLogs
  class BatchRequest < ApplicationRecord
    self.table_name = "llm_logs_batch_requests"

    belongs_to :batch, class_name: "LlmLogs::Batch", optional: true

    enum :status, {
      pending: "pending",
      submitted: "submitted",
      succeeded: "succeeded",
      failed: "failed",
      fell_back: "fell_back"
    }, default: :pending

    validates :custom_id, presence: true, uniqueness: true
    validates :purpose, :model, presence: true
  end
end
