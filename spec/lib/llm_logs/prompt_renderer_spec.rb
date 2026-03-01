require "spec_helper"

RSpec.describe LlmLogs::PromptRenderer do
  describe ".render" do
    it "renders Mustache variables" do
      result = LlmLogs::PromptRenderer.render("Hello {{name}}, welcome to {{project}}!", "name" => "Alice", "project" => "Tradebot")
      expect(result).to eq("Hello Alice, welcome to Tradebot!")
    end

    it "does not HTML-escape values" do
      result = LlmLogs::PromptRenderer.render("Analyze: {{data}}", "data" => "<html> & 'quotes'")
      expect(result).to eq("Analyze: <html> & 'quotes'")
    end

    it "handles missing variables as empty strings" do
      result = LlmLogs::PromptRenderer.render("Hello {{name}}!", {})
      expect(result).to eq("Hello !")
    end

    it "supports sections for conditional content" do
      template = "{{#debug}}Debug mode enabled.{{/debug}} Ready."
      expect(LlmLogs::PromptRenderer.render(template, "debug" => true)).to eq("Debug mode enabled. Ready.")
      expect(LlmLogs::PromptRenderer.render(template, "debug" => false)).to eq(" Ready.")
    end

    it "supports list iteration" do
      template = "Tools: {{#tools}}{{.}}, {{/tools}}"
      result = LlmLogs::PromptRenderer.render(template, "tools" => ["RSI", "MACD", "EMA"])
      expect(result).to include("RSI")
      expect(result).to include("MACD")
    end
  end
end
