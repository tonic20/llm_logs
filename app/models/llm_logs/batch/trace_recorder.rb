module LlmLogs
  class Batch
    # Records a completed trace + llm span for a reconciled batch request, mirroring
    # what the synchronous chat.complete auto-instrumentation captures (model, provider,
    # tokens, cost). Cost applies the 50% Batch API discount.
    module TraceRecorder
      BATCH_COST_MULTIPLIER = 0.5

      module_function

      def record(request:, message:, provider:)
        trace = nil
        metadata = request.routing.merge("execution_mode" => "batch")
        LlmLogs.trace(request.purpose, metadata: metadata) do |t|
          trace = t
          prompt_version_id = request.routing["prompt_version_id"]
          t.update_column(:prompt_version_id, prompt_version_id) if prompt_version_id

          span = LlmLogs::Tracer.start_span(
            name: "batch.complete",
            span_type: "llm",
            model: message.model_id || request.model,
            provider: provider.to_s,
            input: request.payload["input"]
          )
          span.update!(
            output: { "content" => span.serialize_content(message.content) },
            input_tokens: message.input_tokens,
            output_tokens: message.output_tokens,
            cost: compute_cost(message)
          )
          span.finish
        end
        trace
      end

      def compute_cost(message)
        model_info = RubyLLM.models.find(message.model_id)
        return nil unless model_info&.input_price_per_million && model_info&.output_price_per_million

        raw = (message.input_tokens.to_f * model_info.input_price_per_million +
               message.output_tokens.to_f * model_info.output_price_per_million) / 1_000_000
        (raw * BATCH_COST_MULTIPLIER).round(6)
      rescue StandardError
        nil
      end
    end
  end
end
