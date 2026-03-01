module LlmLogs
  class Trace < ApplicationRecord
    has_many :spans, dependent: :destroy

    validates :name, presence: true
    validates :status, presence: true, inclusion: { in: %w[running completed error] }
    validates :started_at, presence: true

    scope :recent, -> { order(started_at: :desc) }
    scope :by_project, ->(project) { where(project: project) if project.present? }
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

    def root_spans
      spans.where(parent_span_id: nil).order(:started_at)
    end

    private

    def rollup_stats!
      self.total_input_tokens = spans.sum(:input_tokens)
      self.total_output_tokens = spans.sum(:output_tokens)
      self.total_cost = spans.sum(:cost)
    end
  end
end
