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
            cost: compute_cost(message, request: request, provider: provider)
          )
          span.finish
        end
        trace
      end

      # Prices the request at the submitted model's standard rates for this provider (the
      # Bedrock id, e.g. us.anthropic.claude-haiku-4-5-...), falling back to the id the result
      # reports (a native Anthropic id resolves to the anthropic provider's rates). nil when
      # neither is in the registry or the registry has no price for the tokens used.
      def compute_cost(message, request:, provider:)
        model = pricing_model(request.model, provider) || pricing_model(message.model_id, nil)
        return nil unless model

        tokens = RubyLLM::Tokens.new(input: message.input_tokens.to_i, output: message.output_tokens.to_i)
        total = model.cost_for(tokens).total
        total && (total * BATCH_COST_MULTIPLIER).round(6)
      rescue StandardError
        nil
      end

      def pricing_model(model_id, provider)
        return nil if model_id.blank?

        provider.present? ? RubyLLM.models.find(model_id, provider: provider) : RubyLLM.models.find(model_id)
      rescue RubyLLM::ModelNotFoundError
        nil
      end
    end
  end
end
