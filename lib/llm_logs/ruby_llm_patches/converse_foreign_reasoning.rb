module LlmLogs
  module RubyLLMPatches
    # Bedrock reasoning replayed only to Anthropic models on Converse.
    #
    # ruby_llm 2.0.0 (Protocols::Converse::Chat#format_thinking_blocks) replays every assistant
    # message's reasoning (raw_reasoning["converse"] blocks, else thinking text/signature) as
    # reasoningContent whatever the target model. Upstream only strips thinking a *different
    # provider* produced (Protocol#foreign_thinking?), and Claude and GPT are both "bedrock",
    # so a chat Claude answered and GPT continues fails with 400 "This model doesn't support
    # the reasoningContent.reasoningText.text field for assistant message".
    #
    # Only Anthropic models need (and accept) their signed reasoning back, so any other model
    # whose id names its vendor (openai., amazon., ...) gets none. Anthropic targets, and
    # application-inference-profile ARNs whose id names no model, go to super unchanged.
    module ConverseForeignReasoning
      ANTHROPIC = /\Aanthropic\./
      NAMED_VENDOR = /\A[a-z0-9-]+\./

      private

      def format_thinking_blocks(msg)
        return super unless llm_logs_foreign_reasoning_target?

        []
      end

      def llm_logs_foreign_reasoning_target?
        id = foundation_model_id(model&.id)
        NAMED_VENDOR.match?(id) && !ANTHROPIC.match?(id)
      end

      def self.install!
        RubyLLMPatches.prepend_checked(
          RubyLLM::Protocols::Converse, self, %i[format_thinking_blocks foundation_model_id model]
        )
      end
    end
  end
end
