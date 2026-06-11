module LlmLogs
  class Batch
    class FlushJob < ::ActiveJob::Base
      queue_as :default

      def perform(purpose)
        models = LlmLogs::BatchRequest.pending.where(purpose: purpose).distinct.pluck(:model)
        models.each { |model| LlmLogs::Batch.submit_pending(purpose: purpose, model: model) }
      end
    end
  end
end
