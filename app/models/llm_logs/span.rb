module LlmLogs
  class Span < ApplicationRecord
    belongs_to :trace, counter_cache: true
    belongs_to :parent_span, class_name: "LlmLogs::Span", optional: true
    has_many :child_spans, class_name: "LlmLogs::Span", foreign_key: :parent_span_id, dependent: :nullify

    validates :name, presence: true
    validates :span_type, presence: true, inclusion: { in: %w[llm tool custom] }
    validates :status, presence: true, inclusion: { in: %w[ok error] }
    validates :started_at, presence: true

    def finish
      update!(
        completed_at: Time.current,
        duration_ms: (Time.current - started_at) * 1000
      )

      # Restore parent span as current
      Thread.current[:llm_logs_span] = parent_span
    end

    def record_response(message)
      self.output = { content: message.content.to_s }
      self.input_tokens = message.input_tokens
      self.output_tokens = message.output_tokens
      self.cached_tokens = message.cached_tokens
    end

    def record_error(exception)
      self.status = "error"
      self.error_message = "#{exception.class}: #{exception.message}"
    end

    def set_attribute(key, value)
      self.metadata = (metadata || {}).merge(key => value)
    end
  end
end
