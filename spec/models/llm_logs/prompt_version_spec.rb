require "spec_helper"

RSpec.describe LlmLogs::PromptVersion do
  describe "#traces" do
    it "returns traces linked to this version" do
      prompt = LlmLogs::Prompt.create!(slug: "test", name: "Test")
      prompt.update_content!(messages: [{ "role" => "user", "content" => "Hello" }])
      version = prompt.current_version

      trace = LlmLogs::Trace.create!(
        name: "test", started_at: Time.current, status: "running",
        prompt_version: version
      )

      expect(version.traces).to eq([trace])
    end

    it "nullifies traces when version is destroyed" do
      prompt = LlmLogs::Prompt.create!(slug: "test", name: "Test")
      prompt.update_content!(messages: [{ "role" => "user", "content" => "v1" }])
      prompt.update_content!(messages: [{ "role" => "user", "content" => "v2" }])
      version = prompt.version(1)

      trace = LlmLogs::Trace.create!(
        name: "test", started_at: Time.current, status: "running",
        prompt_version: version
      )

      version.destroy!
      expect(trace.reload.prompt_version_id).to be_nil
    end
  end
end
