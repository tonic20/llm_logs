require "mustache"

module LlmLogs
  class PromptVersion < ApplicationRecord
    belongs_to :prompt
    has_many :traces, class_name: "LlmLogs::Trace", dependent: :nullify

    validates :version_number, presence: true, uniqueness: { scope: :prompt_id }
    validates :messages, presence: true
    validate :reasoning_effort_is_supported

    def reasoning_effort
      return nil unless model_params.is_a?(Hash)

      model_params["reasoning_effort"] || model_params[:reasoning_effort]
    end

    def variables
      messages.flat_map { |msg| msg["content"].to_s.scan(/\{\{[#^]?([^\/}]+)\}\}/) }.flatten.uniq.sort
    end

    def render(variables = {})
      merged = (default_variables || {}).merge(variables.stringify_keys)

      rendered_messages = messages.map do |msg|
        {
          role: msg["role"],
          content: LlmLogs::PromptRenderer.render(msg["content"], merged)
        }
      end

      params = { messages: rendered_messages }
      params[:model] = model if model.present?
      params.merge!(model_params.symbolize_keys) if model_params.present?
      params
    end

    private

    # Providers reject an unknown effort tier at request time; catching it here means
    # a typo in the admin form or a prompt .md fails loudly at write time instead.
    def reasoning_effort_is_supported
      return if reasoning_effort.blank?

      allowed = LlmLogs.reasoning_effort_options
      return if allowed.include?(reasoning_effort.to_s)

      errors.add(:model_params, "reasoning_effort #{reasoning_effort.inspect} is not supported (expected one of: #{allowed.join(", ")})")
    end
  end
end
