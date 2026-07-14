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

    def self.adapter_for(provider)
      LlmLogs.batch_adapters.fetch(provider.to_sym) do
        raise ArgumentError, "no batch adapter registered for provider #{provider.inspect}"
      end
    end

    def self.batchable?(model)
      return false unless LlmLogs.batch_enabled?

      !batch_provider_for(model).nil?
    end

    # Which batch provider (if any) serves this model. Bedrock wins for Claude models when
    # the Bedrock adapter is configured; otherwise fall back to the OpenAI provider when the
    # model resolves there; otherwise nil (run synchronously).
    def self.batch_provider_for(model)
      return :bedrock if bedrock_serves?(model)
      return :openai_responses if openai_serves?(model)

      nil
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

    def self.openai_serves?(model)
      return false unless defined?(RubyLLM::Providers::OpenAIResponses)

      servable_by_batch_provider?(model)
    end

    # The batch path submits via RubyLLM.batch(provider: batch_provider). A model is
    # only batchable if that provider can actually serve it -- i.e. the model resolves
    # under batch_provider. Models that belong to a different provider (e.g. Bedrock /
    # Anthropic) don't resolve there, so they return false and the caller runs them
    # synchronously instead of enqueueing work that would fail at submit time.
    def self.servable_by_batch_provider?(model)
      RubyLLM::Models.resolve(
        model, provider: LlmLogs.batch_provider, assume_exists: false, config: RubyLLM.config
      )
      true
    rescue RubyLLM::ModelNotFoundError
      false
    end
  end
end
