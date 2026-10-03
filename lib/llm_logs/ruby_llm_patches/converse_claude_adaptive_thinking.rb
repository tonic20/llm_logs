module LlmLogs
  module RubyLLMPatches
    # Adaptive thinking for adaptive-only Claude models on Bedrock Converse.
    # Backport of crmne/ruby_llm#1025 ("Think adaptively on adaptive-only Claude via Converse").
    #
    # ruby_llm 2.0.0 (Protocols::Converse::Chat#format_reasoning_fields) turns a Claude
    # reasoning effort into a fixed budget, `additionalModelRequestFields: {reasoning_config:
    # {type: "enabled", budget_tokens: N}}`, sized from the Converse budgetTokens schema.
    # Claude models that only think adaptively (the registry advertises an effort option and
    # no budget_tokens option: Sonnet 5, Opus 4.7/4.8/5, Fable 5) reject it with
    # `"thinking.type.enabled" is not supported for this model. Use "thinking.type.adaptive"
    # and "output_config.effort"`, and with_thinking(true) sends no thinking at all. They take
    # `{thinking: {type: "adaptive"}, output_config: {effort: "low"}}`, the rule upstream's own
    # Anthropic protocol already applies (Protocols::Anthropic::Chat#thinking_mode).
    #
    # For an adaptive-only Claude target with no budget set:
    # - effort other than "none": adaptive thinking, effort in output_config (every advertised
    #   tier, xhigh and max included);
    # - no effort (with_thinking(true), or a display alone): adaptive thinking alone;
    # - effort "none": nothing.
    # No `display` is sent (Converse has no field for it). Everything else goes to super: any
    # budget, thinking turned off (reasoning_config disabled), budget-style Claude (Haiku 4.5,
    # Sonnet 4.6), GPT, Nova and other vendors.
    #
    # The target is Anthropic under any region prefix (ConverseForeignReasoning::ANTHROPIC).
    # A model with no reasoning options of its own (an unregistered id, such as an "in."
    # inference profile) takes them from a Bedrock registry entry for the same foundation model.
    module ConverseClaudeAdaptiveThinking
      ANTHROPIC = ConverseForeignReasoning::ANTHROPIC
      REGION = /\A[a-z0-9-]+\.(?=anthropic\.)/

      private

      def format_reasoning_fields(thinking, model, max_output_tokens = nil)
        return super unless thinking&.enabled? && thinking.enabled != false && thinking.budget.nil?
        return super unless llm_logs_adaptive_only_claude?(model)

        effort = thinking.effort.to_s
        return nil if effort == "none"
        return {thinking: {type: "adaptive"}} if effort.empty?

        {thinking: {type: "adaptive"}, output_config: {effort: effort}}
      end

      def llm_logs_adaptive_only_claude?(model)
        id = foundation_model_id(model&.id)
        return false unless ANTHROPIC.match?(id)

        options = llm_logs_reasoning_options(model, id.sub(REGION, ""))
        options.any? { |o| o[:type] == "effort" } && options.none? { |o| o[:type] == "budget_tokens" }
      end

      def llm_logs_reasoning_options(model, bare_id)
        return model.reasoning_options if model.reasoning_options.any?

        sibling = RubyLLM.models.all.find do |candidate|
          candidate.provider == "bedrock" && candidate.reasoning_options.any? &&
            foundation_model_id(candidate.id).sub(REGION, "") == bare_id
        end
        sibling ? sibling.reasoning_options : []
      end

      def self.install!
        RubyLLMPatches.prepend_checked(
          RubyLLM::Protocols::Converse, self, %i[format_reasoning_fields foundation_model_id]
        )
      end
    end
  end
end
