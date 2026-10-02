module LlmLogs
  class Batch < ApplicationRecord
    class UnsupportedAdapter < StandardError; end

    def self.supported_adapter?
      connection.adapter_name == "PostgreSQL"
    end

    def self.require_supported_adapter!
      raise UnsupportedAdapter, "Provider batch execution requires PostgreSQL" unless supported_adapter?
    end

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

    def self.enqueue(purpose:, model:, input:, instructions:, schema:, routing:, temperature: nil, reasoning_effort: nil)
      require_supported_adapter!
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
          "temperature" => temperature,
          "reasoning_effort" => reasoning_effort
        }.compact
      )
    end

    def self.submit_pending(purpose:, model:, metadata: {})
      Submitter.new(purpose: purpose, model: model, metadata: metadata).call
    end

    def reconcile!
      Reconciler.new(self).call
    end

    def self.adapter_for(provider)
      LlmLogs.batch_adapters.fetch(provider.to_sym) do
        raise ArgumentError, "no batch adapter registered for provider #{provider.inspect}"
      end
    end

    def self.batchable?(model)
      return false unless supported_adapter? && LlmLogs.batch_enabled?

      !batch_provider_for(model).nil?
    end

    # Which batch provider (if any) serves this model: :bedrock when the Bedrock adapter is
    # registered and its model_matcher matches, otherwise nil (run synchronously).
    def self.batch_provider_for(model)
      bedrock_serves?(model) ? :bedrock : nil
    end

    # The Bedrock minimum records-per-job floor for this model (0 when Bedrock does not serve it).
    def self.min_records_for(model)
      batch_provider_for(model) == :bedrock ? LlmLogs.bedrock_batch.min_records.to_i : 0
    end

    def self.bedrock_serves?(model)
      config = LlmLogs.bedrock_batch
      return false if config.nil?
      return false unless LlmLogs.batch_adapters.key?(:bedrock)

      matcher = config.model_matcher
      matcher.respond_to?(:call) ? matcher.call(model.to_s) : matcher.match?(model.to_s)
    end
  end
end
