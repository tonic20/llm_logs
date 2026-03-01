require "spec_helper"

RSpec.describe "LlmLogs::Prompts", type: :request do
  describe "GET /llm_logs/prompts" do
    it "renders the prompts index" do
      LlmLogs::Prompt.create!(slug: "greeting", name: "Greeting")
      get "/llm_logs/prompts"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Greeting")
    end
  end

  describe "GET /llm_logs/prompts/new" do
    it "renders the new form" do
      get "/llm_logs/prompts/new"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("New Prompt")
    end
  end

  describe "POST /llm_logs/prompts" do
    it "creates a prompt with a version" do
      expect {
        post "/llm_logs/prompts", params: {
          prompt: {
            slug: "greeting",
            name: "Greeting",
            model: "claude-sonnet-4",
            messages: {
              "0" => { role: "system", content: "You are helpful." },
              "1" => { role: "user", content: "Hello {{name}}" }
            }
          }
        }
      }.to change(LlmLogs::Prompt, :count).by(1)
        .and change(LlmLogs::PromptVersion, :count).by(1)

      prompt = LlmLogs::Prompt.last
      expect(response).to redirect_to("/llm_logs/prompts/#{prompt.id}")
      expect(prompt.current_version.messages.size).to eq(2)
    end
  end

  describe "GET /llm_logs/prompts/:id" do
    it "renders the prompt detail" do
      prompt = LlmLogs::Prompt.create!(slug: "greeting", name: "Greeting")
      prompt.update_content!(
        messages: [{ "role" => "user", "content" => "Hello {{name}}" }],
        model: "claude-sonnet-4"
      )

      get "/llm_logs/prompts/#{prompt.id}"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Greeting")
      expect(response.body).to include("Hello {{name}}")
    end
  end

  describe "DELETE /llm_logs/prompts/:id" do
    it "deletes the prompt and redirects" do
      prompt = LlmLogs::Prompt.create!(slug: "greeting", name: "Greeting")
      expect {
        delete "/llm_logs/prompts/#{prompt.id}"
      }.to change(LlmLogs::Prompt, :count).by(-1)

      expect(response).to redirect_to("/llm_logs/prompts")
    end
  end
end
