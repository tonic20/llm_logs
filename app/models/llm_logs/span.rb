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

      # Restore parent span as current (Fiber[] so child fibers inherit it)
      LlmLogs::Tracer.current_span = parent_span
    end

    # +message+ is a RubyLLM 2.x Message (or anything with +content+ and +tokens+).
    def record_response(message)
      self.output = { content: serialize_content(message.content) }
      record_tokens(message.tokens)
    end

    # Copies a RubyLLM::Tokens onto the span. +input+ is non-cached input (RubyLLM 2.x no
    # longer subtracts cache buckets from it); cache writes and thinking have no column and
    # go to metadata.
    def record_tokens(tokens)
      return unless tokens

      self.input_tokens = tokens.input
      self.output_tokens = tokens.output
      self.cached_tokens = tokens.cache_read
      set_attribute("cache_write_tokens", tokens.cache_write) unless tokens.cache_write.nil?
      set_attribute("thinking_tokens", tokens.thinking) unless tokens.thinking.nil?
    end

    # Structured (schema) responses arrive as a Hash/Array; keep them as-is so the
    # JSON `output` column stores real JSON and the UI renders nested fields. Calling
    # `.to_s` here would serialize a Hash with Ruby inspect syntax ("key" => "value"),
    # which is not valid JSON and shows up as an escaped blob in the dashboard.
    def serialize_content(content)
      content.is_a?(Hash) || content.is_a?(Array) ? content : content.to_s
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
