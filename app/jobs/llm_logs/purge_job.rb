module LlmLogs
  # Deletes traces (and their spans) started more than LlmLogs.retention_days ago. Schedule it
  # from the host app, e.g. daily; a nil retention_days keeps everything.
  class PurgeJob < ::ActiveJob::Base
    queue_as :default

    BATCH_SIZE = 500

    def perform
      days = LlmLogs.retention_days
      return if days.nil?

      LlmLogs::Trace.where(started_at: ...days.days.ago).in_batches(of: BATCH_SIZE) do |traces|
        trace_ids = traces.ids
        LlmLogs::BatchRequest.where(trace_id: trace_ids).update_all(trace_id: nil)
        LlmLogs::Span.where(trace_id: trace_ids).delete_all
        LlmLogs::Trace.where(id: trace_ids).delete_all
      end
    end
  end
end
