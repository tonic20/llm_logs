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

        begin
          result = super(&block)
          span.record_response(result)
          result
        rescue => e
          span.record_error(e)
          raise
        ensure
          span.finish
        end
      end

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
