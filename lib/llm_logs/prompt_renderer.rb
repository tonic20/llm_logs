require "mustache"

module LlmLogs
  class PromptRenderer < Mustache
    # Disable HTML escaping — LLM prompts are plain text
    def escapeHTML(str)
      str
    end

    def self.render(template_string, variables = {})
      renderer = new
      renderer.template = template_string
      variables.each { |key, value| renderer[key] = value }
      renderer.render
    end
  end
end
