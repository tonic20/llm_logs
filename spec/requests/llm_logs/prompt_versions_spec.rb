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

    it "shows trace count when version has linked traces" do
      version = prompt.version(1)
      LlmLogs::Trace.create!(
        name: "test", started_at: Time.current, status: "completed",
        prompt_version: version
      )

      get "/llm_logs/prompts/#{prompt.id}/versions/#{version.id}"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("1 trace")
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

  describe "DELETE /llm_logs/prompts/:prompt_id/versions/:id" do
    it "deletes a non-current version" do
      version_1 = prompt.version(1)

      expect {
        delete "/llm_logs/prompts/#{prompt.id}/versions/#{version_1.id}"
      }.to change(LlmLogs::PromptVersion, :count).by(-1)

      expect(response).to redirect_to("/llm_logs/prompts/#{prompt.id}/versions")
    end

    it "prevents deleting the current version" do
      current = prompt.current_version

      expect {
        delete "/llm_logs/prompts/#{prompt.id}/versions/#{current.id}"
      }.not_to change(LlmLogs::PromptVersion, :count)

      expect(response).to redirect_to("/llm_logs/prompts/#{prompt.id}/versions")
      follow_redirect!
      expect(response.body).to include("Cannot delete the current active version")
    end

    it "nullifies linked traces when version is deleted" do
      version_1 = prompt.version(1)
      trace = LlmLogs::Trace.create!(
        name: "test", started_at: Time.current, status: "completed",
        prompt_version: version_1
      )

      delete "/llm_logs/prompts/#{prompt.id}/versions/#{version_1.id}"
      expect(trace.reload.prompt_version_id).to be_nil
    end
  end

  describe "GET /llm_logs/prompts/:prompt_id/versions/compare" do
    it "renders a side-by-side diff of two versions" do
      get "/llm_logs/prompts/#{prompt.id}/versions/compare", params: { a: 1, b: 2 }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("v1")
      expect(response.body).to include("v2")
      expect(response.body).to include("v1 content")
      expect(response.body).to include("v2 content")
    end

    it "redirects when a param is missing" do
      get "/llm_logs/prompts/#{prompt.id}/versions/compare", params: { a: 1 }
      expect(response).to redirect_to("/llm_logs/prompts/#{prompt.id}/versions")
      follow_redirect!
      expect(response.body).to include("Select two different versions")
    end

    it "redirects when both params are the same" do
      get "/llm_logs/prompts/#{prompt.id}/versions/compare", params: { a: 1, b: 1 }
      expect(response).to redirect_to("/llm_logs/prompts/#{prompt.id}/versions")
      follow_redirect!
      expect(response.body).to include("Select two different versions")
    end

    it "redirects when a version is not found" do
      get "/llm_logs/prompts/#{prompt.id}/versions/compare", params: { a: 1, b: 999 }
      expect(response).to redirect_to("/llm_logs/prompts/#{prompt.id}/versions")
      follow_redirect!
      expect(response.body).to include("Version not found")
    end
  end
end
