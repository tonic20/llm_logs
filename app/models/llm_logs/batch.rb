module LlmLogs
  class Batch < ApplicationRecord
    self.table_name = "llm_logs_batches"

    has_many :requests, class_name: "LlmLogs::BatchRequest", dependent: :destroy

    enum :status, {
      pending: "pending",
      submitted: "submitted",
      completed: "completed",
      failed: "failed",
      expired: "expired",
      reconciled: "reconciled"
    }, default: :pending

    validates :purpose, :model, presence: true

    scope :recent, -> { order(created_at: :desc) }
    scope :unreconciled, -> { where.not(status: %i[reconciled failed expired]) }

    def self.enqueue(purpose:, model:, input:, instructions:, schema:, routing:, temperature: nil)
      BatchRequest.create!(
        purpose: purpose,
        model: model,
        status: :pending,
        custom_id: "req_#{SecureRandom.hex(8)}",
        routing: routing,
        payload: {
          "input" => input,
          "instructions" => instructions,
          "schema" => schema,
          "temperature" => temperature
        }.compact
      )
    end

    def self.submit_pending(purpose:, model:, metadata: {})
      Submitter.new(purpose: purpose, model: model, metadata: metadata).call
    end

    def reconcile!
      Reconciler.new(self).call
    end

    def self.batchable?(model)
      return false unless LlmLogs.batch_enabled?

      !defined?(RubyLLM::Providers::OpenAIResponses).nil?
    end
  end
end
