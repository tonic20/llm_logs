module LlmLogs
  module Instrumentation
    # Records RubyLLM 2.x chat activity as llm_logs spans by subscribing to the
    # events RubyLLM emits for observability adapters (docs/_advanced/instrumentation.md):
    #
    #   chat.ruby_llm      -- one per model request (RubyLLM::Chat#generate_once): an "llm" span
    #                         per provider round. Wraps every transport retry of that round, so a
    #                         round that fails after its retries surfaces as :exception_object.
    #                         With fallbacks, each model tried gets its own span.
    #   tool_call.ruby_llm -- one per local tool execution (RubyLLM::Chat#execute_tool): a "tool" span.
    #
    # Rounds and tools are siblings under the current span/trace:
    #   trace -> llm (round 1, asks for a tool) -> tool.x -> llm (round 2, final answer)
    #
    # The subscription is global (every RubyLLM::Chat, including acts_as_chat's to_llm and
    # RubyLLM::Agent), but only fires while RubyLLM's instrumenter is ActiveSupport::Notifications,
    # which RubyLLM's Railtie sets by default.
    module RubyLlmChat
      SPAN_KEY = :llm_logs_span
      USAGE_START_KEY = :llm_logs_usage_start

      class << self
        def install!
          return if installed?

          RubyLLM.config.instrumenter ||= ActiveSupport::Notifications
          @subscribers = [
            ActiveSupport::Notifications.subscribe("chat.ruby_llm", ChatSubscriber.new),
            ActiveSupport::Notifications.subscribe("tool_call.ruby_llm", ToolSubscriber.new)
          ]
        end

        def uninstall!
          Array(@subscribers).each { |subscriber| ActiveSupport::Notifications.unsubscribe(subscriber) }
          @subscribers = nil
        end

        def installed?
          !@subscribers.nil?
        end

        # Instrumentation must never break the LLM call it observes. ActiveSupport re-raises
        # subscriber exceptions into the instrumented block, so every hook rescues.
        def guard
          yield
        rescue StandardError => e
          Rails.logger&.error("[llm_logs] instrumentation error: #{e.class}: #{e.message}")
          nil
        end
      end

      # Serializers shared by both subscribers.
      module Serialize
        module_function

        def messages(list)
          Array(list).map { |message| message_entry(message) }
        end

        def message_entry(message)
          entry = {role: message.role, content: message.content}
          calls = tool_calls(message.tool_calls)
          entry[:tool_calls] = calls if calls
          entry[:tool_call_id] = message.tool_call_id if message.tool_call_id
          entry
        end

        def tool_calls(calls)
          return nil if calls.nil? || calls.empty?

          calls.values.map { |call| {id: call.id, name: call.name, arguments: call.arguments} }
        end

        # Structured (schema) answers are JSON text in 2.x; store the parsed Hash so the
        # UI renders nested fields instead of an escaped string.
        def response(message, schema:)
          content = message.content
          content = parse_json(content) if schema && content.is_a?(String) && !content.empty?
          output = {content: content}
          calls = tool_calls(message.tool_calls)
          output[:tool_calls] = calls if calls
          output[:thinking] = message.thinking.text if message.thinking&.text.present?
          output
        end

        def parse_json(text)
          JSON.parse(text)
        rescue JSON::ParserError
          text
        end

        def tool_result(result)
          case result
          when Hash then result
          when Array then {result: result}
          else {result: result.to_s}
          end
        end
      end

      class ChatSubscriber
        def start(_name, _id, payload)
          RubyLlmChat.guard do
            next unless LlmLogs.enabled?

            chat = payload[:chat]
            payload[USAGE_START_KEY] = chat.usage_entries.length if chat.respond_to?(:usage_entries)
            payload[SPAN_KEY] = LlmLogs::Tracer.start_span(
              name: "chat.complete",
              span_type: "llm",
              model: payload[:model],
              provider: payload[:provider],
              input: Serialize.messages(payload[:input_messages]),
              metadata: request_metadata(payload)
            )
          end
        end

        def finish(_name, _id, payload)
          span = payload.delete(SPAN_KEY)
          return unless span

          RubyLlmChat.guard do
            if (error = payload[:exception_object])
              span.record_error(error)
            else
              span.output = Serialize.response(payload[:response], schema: payload[:schema])
              span.set_attribute("finish_reason", payload[:response].finish_reason&.to_s)
              response_model = payload[:response_model]
              span.set_attribute("response_model", response_model) if response_model && response_model != payload[:model]
            end
            record_usage(span, payload)
          end
        ensure
          RubyLlmChat.guard { span&.finish }
        end

        private

        def request_metadata(payload)
          {
            "streaming" => payload[:streaming],
            "tools" => Array(payload[:tools]).map(&:to_s),
            "temperature" => payload[:temperature],
            "thinking" => thinking_metadata(payload[:thinking]),
            "schema" => payload[:schema] && payload[:schema][:name]
          }.compact
        end

        def thinking_metadata(thinking)
          return nil unless thinking

          {"effort" => thinking.effort&.to_s, "budget" => thinking.budget, "enabled" => thinking.enabled}.compact.presence
        end

        # Tokens and cost of every transport attempt this round made (retries included), read
        # from the chat's usage ledger. Falls back to the event's tokens/cost when the ledger is
        # unavailable. A failed attempt whose usage is unknown (e.g. a timeout that may have
        # been billed) is left out of the cost and flagged with cost_complete: false.
        def record_usage(span, payload)
          entries = round_usage_entries(payload)
          if entries
            tokens = RubyLLM::Tokens.aggregate(entries.map(&:tokens))
            cost = RubyLLM::Cost.aggregate(entries.map(&:cost))
            span.set_attribute("attempts", entries.size) if entries.size > 1
            span.set_attribute("cost_complete", false) unless entries.all?(&:cost_available?)
          else
            tokens = payload[:tokens]
            cost = payload[:cost]
          end
          span.record_tokens(tokens)
          span.cost = cost&.total
        end

        def round_usage_entries(payload)
          start = payload[USAGE_START_KEY]
          chat = payload[:chat]
          return nil unless start && chat.respond_to?(:usage_entries)

          chat.usage_entries.drop(start)
        end
      end

      class ToolSubscriber
        def start(_name, _id, payload)
          RubyLlmChat.guard do
            next unless LlmLogs.enabled?

            payload[SPAN_KEY] = LlmLogs::Tracer.start_span(
              name: "tool.#{payload[:tool_name]}",
              span_type: "tool",
              input: payload[:tool_arguments],
              metadata: {tool_name: payload[:tool_name].to_s, tool_call_id: payload[:tool_call_id]}.compact
            )
          end
        end

        def finish(_name, _id, payload)
          span = payload.delete(SPAN_KEY)
          return unless span

          RubyLlmChat.guard do
            if (error = payload[:exception_object])
              span.record_error(error)
            else
              span.output = Serialize.tool_result(payload[:result])
            end
          end
        ensure
          RubyLlmChat.guard { span&.finish }
        end
      end
    end
  end
end
