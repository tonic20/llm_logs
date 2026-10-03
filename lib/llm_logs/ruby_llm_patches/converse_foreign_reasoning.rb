module LlmLogs
  module RubyLLMPatches
    # Bedrock Converse replays a message's reasoning only to a model of the same family.
    #
    # ruby_llm 2.0.0 (Protocols::Converse::Chat#format_thinking_blocks) replays every assistant
    # message's reasoning (raw_reasoning["converse"] blocks, else thinking text/signature) as
    # reasoningContent whatever the target model. Upstream only strips thinking a *different
    # provider* produced (Protocol#foreign_thinking?), and Claude and GPT are both "bedrock".
    # So a chat Claude answered and GPT continues fails with 400 "This model doesn't support
    # the reasoningContent.reasoningText.text field for assistant message", and a chat GPT
    # answered and Claude continues hands Claude GPT's encrypted reasoning (redactedContent,
    # or a reasoningText with an empty text and GPT's blob as signature for rows migrated from
    # 1.16), which Claude cannot validate.
    #
    # The family of a model id is "anthropic", "openai", or the vendor segment of any other
    # Bedrock id ("amazon", "meta", ...), whatever region prefix it carries. The producer is
    # RubyLLM::Message#model (the reply's model, or for a restored row the model of its last
    # successful ruby_llm_usages entry).
    #
    # - Producer known and of another family: no reasoning is replayed.
    # - Anthropic target (same family or producer unknown): super, unchanged.
    # - Other named-vendor target (same family or producer unknown): only the redactedContent
    #   blocks in raw_reasoning["converse"] (how GPT keeps its own encrypted reasoning across
    #   tool-call rounds); reasoningText and the thinking text/signature fallback are dropped.
    # - Target whose id names no model (application-inference-profile ARN): super, unchanged.
    #
    # An application inference profile id is opaque, and AWS allows dots in it
    # (".../application-inference-profile/team.prod"), so it names no family as producer or
    # target (backport of crmne/ruby_llm#1026, "Give application inference profiles no vendor").
    # The rest of this module is stricter than #1026 on purpose: for a non-Anthropic target
    # whose producer is unknown or of the same family, upstream replays all the reasoning, while
    # this keeps only redactedContent.
    module ConverseForeignReasoning
      ANTHROPIC = /(?:\A|\.)anthropic\./
      OPENAI = /(?:\A|\.)openai\./
      VENDOR = /\A[a-z0-9-]+(?=\.)/
      APPLICATION_INFERENCE_PROFILE = ":application-inference-profile/"

      private

      def format_thinking_blocks(msg)
        target = llm_logs_model_family(model&.id)
        return super if target.nil?

        producer = llm_logs_model_family(msg.model) if msg.respond_to?(:model)
        return [] if producer && producer != target
        return super if target == "anthropic"

        blocks = msg.raw_reasoning["converse"] || msg.raw_reasoning[:converse] if msg.raw_reasoning.is_a?(Hash)
        kept = Array(blocks).select { |block| llm_logs_redacted_only?(block) }
        RubyLLM::Support::Utils.deep_dup(kept)
      end

      # "anthropic", "openai", another vendor segment, or nil when the id names no model.
      def llm_logs_model_family(model_id)
        return if model_id.to_s.include?(APPLICATION_INFERENCE_PROFILE)

        id = foundation_model_id(model_id)
        return "anthropic" if ANTHROPIC.match?(id)
        return "openai" if OPENAI.match?(id)

        id[VENDOR]
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
