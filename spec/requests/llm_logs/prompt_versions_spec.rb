require "spec_helper"

RSpec.describe "LlmLogs::PromptVersions", type: :request do
  let!(:prompt) { LlmLogs::Prompt.create!(slug: "test", name: "Test Prompt") }

  before do
    prompt.update_content!(messages: [{ "role" => "system", "content" => "v1 content" }], model: "gpt-4")
    prompt.update_content!(messages: [{ "role" => "system", "content" => "v2 content" }], model: "gpt-4o")
  end

  describe "GET /llm_logs/prompts/:prompt_id/versions" do
    it "renders the version history" do
      get "/llm_logs/prompts/#{prompt.id}/versions"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("v1")
      expect(response.body).to include("v2")
    end
  end

  describe "GET /llm_logs/prompts/:prompt_id/versions/:id" do
    it "renders the version detail" do
      version = prompt.version(1)
      get "/llm_logs/prompts/#{prompt.id}/versions/#{version.id}"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("v1 content")
    end
  end

  describe "POST /llm_logs/prompts/:prompt_id/versions/:id/restore" do
    it "creates a new version with the old content" do
      version_1 = prompt.version(1)

      expect {
        post "/llm_logs/prompts/#{prompt.id}/versions/#{version_1.id}/restore"
      }.to change(LlmLogs::PromptVersion, :count).by(1)

      expect(response).to redirect_to("/llm_logs/prompts/#{prompt.id}")

      new_current = prompt.reload.current_version
      expect(new_current.version_number).to eq(3)
      expect(new_current.messages.first["content"]).to eq("v1 content")
      expect(new_current.model).to eq("gpt-4")
      expect(new_current.changelog).to eq("Rollback to version 1")
    end

    it "restoring the current version creates a duplicate copy" do
      current = prompt.current_version

      expect {
        post "/llm_logs/prompts/#{prompt.id}/versions/#{current.id}/restore"
      }.to change(LlmLogs::PromptVersion, :count).by(1)

      new_current = prompt.reload.current_version
      expect(new_current.version_number).to eq(3)
      expect(new_current.messages.first["content"]).to eq("v2 content")
    end
  end
end
