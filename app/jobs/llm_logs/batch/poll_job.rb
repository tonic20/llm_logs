module LlmLogs
  class Batch
    class PollJob < ::ActiveJob::Base
      queue_as :default

      # A placeholder claim (status "pending", no openai_batch_id) is only meant to exist
      # for the sub-second window of Submitter#submit. Anything older died mid-submit
      # (e.g. the worker was killed), so its requests are stranded. Recover them.
      STALE_CLAIM_AFTER = 15.minutes

      def perform
        recover_stale_claims
        LlmLogs::Batch.unreconciled.where.not(provider_batch_id: nil).find_each do |batch|
          batch.reconcile!
        rescue StandardError => e
          Rails.logger.error("[llm_logs] batch #{batch.id} reconcile failed: #{e.class}: #{e.message}")
        end
      end

      private

      def recover_stale_claims
        LlmLogs::Batch
          .where(status: :pending, provider_batch_id: nil)
          .where("created_at < ?", STALE_CLAIM_AFTER.ago)
          .find_each do |batch|
            batch.requests.update_all(batch_id: nil, status: :pending)
            batch.destroy
          rescue StandardError => e
            Rails.logger.error("[llm_logs] batch #{batch.id} stale-claim recovery failed: #{e.class}: #{e.message}")
          end
      end
    end
  end
end
