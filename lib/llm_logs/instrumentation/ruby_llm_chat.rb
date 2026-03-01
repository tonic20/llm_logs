module LlmLogs
  module Instrumentation
    module RubyLlmChat
      def complete(&block)
        return super unless LlmLogs.enabled?

        span = LlmLogs::Tracer.start_span(
          name: "chat.complete",
          span_type: "llm",
          model: @model&.id,
          provider: @model&.provider,
          input: messages.map { |m| { role: m.role, content: m.content.to_s } }
        )

        messages_before = messages.size

        begin
          result = super(&block)
          span.record_response(result)
          span.cost = llm_logs_compute_cost(result)
          result
        rescue => e
          span.record_error(e)
          llm_logs_capture_partial_tokens(span, messages_before)
          raise
        ensure
          span.finish
        end
      end

      private

      def llm_logs_capture_partial_tokens(span, messages_before)
        assistant_msg = messages[messages_before..].find { |m| m.role == :assistant }
        return unless assistant_msg&.input_tokens

        span.input_tokens = assistant_msg.input_tokens
        span.output_tokens = assistant_msg.output_tokens
        span.cached_tokens = assistant_msg.cached_tokens
        span.cost = llm_logs_compute_cost(assistant_msg)
      rescue StandardError
        nil
      end

      def llm_logs_compute_cost(message)
        model_info = llm_logs_resolve_pricing_model
        return unless model_info

        input_price = model_info.input_price_per_million
        output_price = model_info.output_price_per_million
        return unless input_price && output_price

        (message.input_tokens.to_f * input_price + message.output_tokens.to_f * output_price) / 1_000_000
      end

      def llm_logs_resolve_pricing_model
        return @model if @model&.input_price_per_million

        RubyLLM.models.find(@model.id) if @model&.id
      rescue StandardError
        nil
      end

      public

      def execute_tool(tool_call)
        return super unless LlmLogs.enabled?

        span = LlmLogs::Tracer.start_span(
          name: "tool.#{tool_call.name}",
          span_type: "tool",
          metadata: { tool_name: tool_call.name, arguments: tool_call.arguments }
        )

        begin
          result = super
          span.set_attribute("tool.halted", true) if defined?(RubyLLM::Tool::Halt) && result.is_a?(RubyLLM::Tool::Halt)
          result
        rescue => e
          span.record_error(e)
          raise
        ensure
          span.finish
        end
      end
    end
  end
end
