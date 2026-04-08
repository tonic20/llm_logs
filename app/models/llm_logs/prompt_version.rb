require "mustache"

module LlmLogs
  class PromptVersion < ApplicationRecord
    belongs_to :prompt
    has_many :traces, class_name: "LlmLogs::Trace", dependent: :nullify

    validates :version_number, presence: true, uniqueness: { scope: :prompt_id }
    validates :messages, presence: true

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
  end
end
