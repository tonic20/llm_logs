module LlmLogs
  class Trace < ApplicationRecord
    has_many :spans, dependent: :destroy
    has_one :batch_request, class_name: "LlmLogs::BatchRequest", dependent: :nullify
    belongs_to :prompt_version, class_name: "LlmLogs::PromptVersion", optional: true

    validates :name, presence: true
    validates :status, presence: true, inclusion: { in: %w[running completed error] }
    validates :started_at, presence: true

    scope :recent, -> { order(started_at: :desc) }
    scope :by_status, ->(status) { where(status: status) if status.present? }

    def complete!
      return if status == "completed"

      rollup_stats!
      update!(
        status: "completed",
        completed_at: Time.current,
        duration_ms: (Time.current - started_at) * 1000
      )
    end

    def fail!
      rollup_stats!
      update!(
        status: "error",
        completed_at: Time.current,
        duration_ms: (Time.current - started_at) * 1000
      )
    end

    def root_spans
      spans.where(parent_span_id: nil).order(:started_at)
    end

    private

    def rollup_stats!
      totals = spans.pick(*%w[input_tokens output_tokens cached_tokens cost].map { |column| Arel.sql("COALESCE(SUM(#{column}), 0)") })
      self.total_input_tokens, self.total_output_tokens, self.total_cached_tokens, self.total_cost = totals
    end
  end
end
