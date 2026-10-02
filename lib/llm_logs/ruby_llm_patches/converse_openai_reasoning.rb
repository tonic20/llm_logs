module LlmLogs
  module RubyLLMPatches
    # GPT reasoning effort on Bedrock Converse.
    #
    # ruby_llm 2.0.0 (Protocols::Converse::Chat#format_reasoning_fields) sends a model
    # without a reasoning-budget schema `additionalModelRequestFields: {reasoning_effort: "low"}`,
    # which Bedrock rejects for OpenAI GPT models (400 unknown_parameter). They take
    # `{reasoning: {effort: "low"}}`, including the "none" tier (fork commit 6391332e).
    #
    # Only OpenAI GPT models on Converse change (us./global./eu.openai.gpt-6-sol, gpt-5.6-*,
    # ...). gpt-oss keeps upstream behaviour (not verified with this shape); Claude (budget
    # schema -> reasoning_config), Nova (reasoningConfig) and explicit budgets go to super.
    module ConverseOpenAIReasoning
      OPENAI_GPT = /\Aopenai\.gpt-(?!oss)/

      private

      def format_reasoning_fields(thinking, model, max_output_tokens = nil)
        return super unless thinking&.enabled? && thinking.budget.nil? && llm_logs_openai_gpt?(model)

        effort = thinking.enabled == false ? "none" : thinking.effort.to_s
        return nil if effort.empty?

        {reasoning: {effort: effort}}
      end

      def llm_logs_openai_gpt?(model)
        OPENAI_GPT.match?(foundation_model_id(model&.id))
      end

      def self.install!
        RubyLLMPatches.prepend_checked(
          RubyLLM::Protocols::Converse, self, %i[format_reasoning_fields foundation_model_id]
        )
      end
    end
  end
end
