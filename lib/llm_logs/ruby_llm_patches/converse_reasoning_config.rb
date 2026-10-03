require "json"

module LlmLogs
  module RubyLLMPatches
    # Reasoning effort as the reasoning_config value on Bedrock Converse.
    # Backport of crmne/ruby_llm#1025 ("Send reasoning_config to models that publish it").
    #
    # ruby_llm 2.0.0 (Protocols::Converse::Chat#format_reasoning_fields) sends the effort of a
    # model without a reasoning-budget schema as `additionalModelRequestFields:
    # {reasoning_effort: "low"}`, which Bedrock rejects for OpenAI GPT models (400
    # unknown_parameter). Their Converse additionalRequestFieldsSchema publishes
    # `{"reasoning_config": {"type": "enum", "enum": ["none", "low", ...]}}`, and they take the
    # effort as that value: `{reasoning_config: "low"}` ("none" turns reasoning off).
    #
    # Upstream rule, applied as #1025 does: when the model's schema, or the schema of another
    # Bedrock registry entry for the same foundation model, publishes that enum, an effort that
    # would have become reasoning_effort becomes the reasoning_config value, "none" included.
    # Thinking off (reasoning_config disabled), budgets (explicit, or from a budget schema),
    # Nova (reasoningConfig) and an empty effort are unchanged.
    #
    # Fallback (not in #1025): OpenAI GPT ids with no published schema get the same shape. ruby_llm
    # 2.0.0's packaged registry lacks GPT-6 Sol/Luna, and an app catalog that registers them
    # without Converse metadata leaves them schema-less. The match is prefix-agnostic (upstream
    # REGION_PREFIXES lacks "in." in 2.0.0) and skips gpt-oss, which publishes no such enum.
    module ConverseReasoningConfig
      OPENAI_GPT = /(?:\A|\.)openai\.gpt-(?!oss)/

      private

      def format_reasoning_fields(thinking, model, max_output_tokens = nil)
        return super unless thinking&.enabled? && thinking.enabled != false
        return super unless llm_logs_reasoning_config?(model)

        effort = thinking.effort.to_s
        return super if effort.empty? || nova_model?(model)
        return super if reasoning_budget(thinking, effort, model, max_output_tokens)

        {reasoning_config: effort}
      end

      def llm_logs_reasoning_config?(model)
        return false unless model

        llm_logs_reasoning_config_schema?(model) || OPENAI_GPT.match?(foundation_model_id(model.id))
      end

      # Bedrock publishes Converse metadata for only some regional entries of a model.
      def llm_logs_reasoning_config_schema?(model)
        return true if llm_logs_publishes_reasoning_config?(model)

        foundation_id = foundation_model_id(model.id)
        RubyLLM.models.all.any? do |candidate|
          candidate.provider == "bedrock" && candidate.id != model.id &&
            foundation_model_id(candidate.id) == foundation_id && llm_logs_publishes_reasoning_config?(candidate)
        end
      end

      def llm_logs_publishes_reasoning_config?(model)
        metadata = RubyLLM::Support::Utils.deep_symbolize_keys(model.metadata || {})
        raw_schema = metadata.dig(:converse, :additionalRequestFieldsSchema)
        return false unless raw_schema.is_a?(String)

        schema = JSON.parse(raw_schema, symbolize_names: true)
        config = schema.is_a?(Hash) ? schema[:reasoning_config] : nil
        config.is_a?(Hash) && config[:type] == "enum"
      rescue JSON::ParserError
        false
      end

      def self.install!
        RubyLLMPatches.prepend_checked(
          RubyLLM::Protocols::Converse, self,
          %i[format_reasoning_fields foundation_model_id nova_model? reasoning_budget]
        )
      end
    end
  end
end
