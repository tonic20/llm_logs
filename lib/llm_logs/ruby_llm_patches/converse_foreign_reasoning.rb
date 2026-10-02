module LlmLogs
  module RubyLLMPatches
    # Bedrock reasoningText replayed only to Anthropic models on Converse.
    #
    # ruby_llm 2.0.0 (Protocols::Converse::Chat#format_thinking_blocks) replays every assistant
    # message's reasoning (raw_reasoning["converse"] blocks, else thinking text/signature) as
    # reasoningContent whatever the target model. Upstream only strips thinking a *different
    # provider* produced (Protocol#foreign_thinking?), and Claude and GPT are both "bedrock",
    # so a chat Claude answered and GPT continues fails with 400 "This model doesn't support
    # the reasoningContent.reasoningText.text field for assistant message".
    #
    # For a model whose id names a non-Anthropic vendor (openai., amazon., ...) only the
    # redactedContent blocks stored in raw_reasoning["converse"] are replayed: that is how GPT
    # keeps its own encrypted reasoning across tool-call rounds. reasoningText blocks and the
    # thinking text/signature fallback (which only yields Claude reasoning) are dropped.
    # Anthropic targets, and application-inference-profile ARNs whose id names no model, go to
    # super unchanged.
    module ConverseForeignReasoning
      ANTHROPIC = /\Aanthropic\./
      NAMED_VENDOR = /\A[a-z0-9-]+\./

      private

      def format_thinking_blocks(msg)
        return super unless llm_logs_non_anthropic_target?

        blocks = msg.raw_reasoning["converse"] || msg.raw_reasoning[:converse] if msg.raw_reasoning.is_a?(Hash)
        kept = Array(blocks).select { |block| llm_logs_redacted_only?(block) }
        RubyLLM::Support::Utils.deep_dup(kept)
      end

      def llm_logs_non_anthropic_target?
        id = foundation_model_id(model&.id)
        NAMED_VENDOR.match?(id) && !ANTHROPIC.match?(id)
      end

      def llm_logs_redacted_only?(block)
        content = block["reasoningContent"] || block[:reasoningContent] if block.is_a?(Hash)
        return false unless content.is_a?(Hash)

        content.keys.map(&:to_s) == ["redactedContent"]
      end

      def self.install!
        RubyLLMPatches.prepend_checked(
          RubyLLM::Protocols::Converse, self, %i[format_thinking_blocks foundation_model_id model]
        )
      end
    end
  end
end
