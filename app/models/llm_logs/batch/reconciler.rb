module LlmLogs
  class Batch
    # Resumes a submitted batch by id, and once terminal, records a trace per request,
    # routes each result to its registered handler, and updates statuses. Idempotent at
    # the request level (succeeded/failed/fell_back requests are skipped on re-run).
    class Reconciler
      def initialize(batch)
        @batch = batch
      end

      def call
        rubyllm_batch = RubyLLM.batch(id: @batch.openai_batch_id, provider: LlmLogs.batch_provider)
        status = rubyllm_batch.status

        case status
        when "completed"
          reconcile_completed(rubyllm_batch)
        when "failed", "expired", "cancelled"
          fail_all(status)
        end
        @batch
      end

      private

      def reconcile_completed(rubyllm_batch)
        results = rubyllm_batch.results
        error_ids = rubyllm_batch.errors.filter_map { |e| e["custom_id"] }

        @batch.update!(status: :completed, completed_at: Time.current)

        @batch.requests.where.not(status: %i[succeeded failed fell_back]).find_each do |request|
          message = results[request.custom_id]
          if message
            reconcile_success(request, message)
          else
            reconcile_failure(request, "no result for custom_id (in error file: #{error_ids.include?(request.custom_id)})")
          end
        end

        @batch.update!(status: :reconciled, reconciled_at: Time.current)
      end

      def reconcile_success(request, message)
        trace = TraceRecorder.record(request: request, message: message)
        request.assign_attributes(
          result_content: result_content_for(message.content),
          input_tokens: message.input_tokens,
          output_tokens: message.output_tokens,
          cost: trace.total_cost,
          trace_id: trace.id
        )
        handler = LlmLogs.batch_handler(request.purpose)
        handler&.call(request, message)
        request.succeeded!
      rescue StandardError => e
        # The LLM result was produced, but the handler (or persistence) failed. Mark the
        # request failed-with-error rather than a misleading "succeeded" so the dropped
        # result is visible in the dashboard instead of silently lost. The trace/tokens
        # are still recorded (the spend happened); only delivery failed.
        request.update!(status: :failed, error: "handler error: #{e.class}: #{e.message}")
      end

      # `result_content` is a text column. Structured (schema) results arrive as a Hash;
      # store them as JSON so the snapshot stays machine-readable instead of Ruby inspect
      # syntax ("key" => "value").
      def result_content_for(content)
        content.is_a?(Hash) || content.is_a?(Array) ? content.to_json : content.to_s
      end

      def reconcile_failure(request, error)
        request.update!(status: :failed, error: error.to_s)
        invoke_handler(request) { |handler| handler.on_failure(request, error) }
      end

      def fail_all(status)
        # STATUSES does not include "cancelled"; treat a cancelled batch as failed so the
        # batch record stays valid, while preserving the real status in the request error.
        batch_status = status == "cancelled" ? :failed : status.to_sym
        @batch.update!(status: batch_status, completed_at: Time.current)
        @batch.requests.where.not(status: %i[succeeded failed fell_back]).find_each do |request|
          reconcile_failure(request, "batch #{status}")
        end
      end

      def invoke_handler(request)
        handler = LlmLogs.batch_handler(request.purpose)
        return unless handler

        yield handler
      rescue StandardError => e
        request.update!(error: "handler error: #{e.class}: #{e.message}")
      end
    end
  end
end
