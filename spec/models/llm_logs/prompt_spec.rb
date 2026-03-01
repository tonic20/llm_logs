require "spec_helper"

RSpec.describe LlmLogs::Prompt do
  describe "validations" do
    it "requires project, slug, and name" do
      prompt = LlmLogs::Prompt.new
      expect(prompt).not_to be_valid
      expect(prompt.errors[:project]).to include("can't be blank")
      expect(prompt.errors[:slug]).to include("can't be blank")
      expect(prompt.errors[:name]).to include("can't be blank")
    end

    it "enforces unique slug per project" do
      LlmLogs::Prompt.create!(project: "app", slug: "greeting", name: "Greeting")
      dupe = LlmLogs::Prompt.new(project: "app", slug: "greeting", name: "Other")
      expect(dupe).not_to be_valid
    end

    it "allows same slug in different projects" do
      LlmLogs::Prompt.create!(project: "app1", slug: "greeting", name: "Greeting 1")
      prompt = LlmLogs::Prompt.new(project: "app2", slug: "greeting", name: "Greeting 2")
      expect(prompt).to be_valid
    end
  end

  describe ".load" do
    it "finds prompt by project and slug" do
      created = LlmLogs::Prompt.create!(project: "app", slug: "greeting", name: "Greeting")
      loaded = LlmLogs::Prompt.load(project: "app", slug: "greeting")
      expect(loaded).to eq(created)
    end

    it "raises when not found" do
      expect {
        LlmLogs::Prompt.load(project: "app", slug: "missing")
      }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end

  describe "#update_content!" do
    let(:prompt) { LlmLogs::Prompt.create!(project: "app", slug: "greeting", name: "Greeting") }

    it "creates a new version with incrementing number" do
      prompt.update_content!(messages: [{ "role" => "user", "content" => "Hello {{name}}" }], model: "gpt-4")
      prompt.update_content!(messages: [{ "role" => "user", "content" => "Hi {{name}}" }], model: "gpt-4", changelog: "simplified")

      expect(prompt.versions.count).to eq(2)
      expect(prompt.versions.pluck(:version_number)).to eq([1, 2])
      expect(prompt.current_version.changelog).to eq("simplified")
    end
  end

  describe "#build" do
    let(:prompt) { LlmLogs::Prompt.create!(project: "app", slug: "greeting", name: "Greeting") }

    before do
      prompt.update_content!(
        messages: [
          { "role" => "system", "content" => "You are a helpful assistant for {{project}}." },
          { "role" => "user", "content" => "Hello, my name is {{name}}." }
        ],
        model: "claude-sonnet-4",
        model_params: { "temperature" => 0.3, "max_tokens" => 1024 }
      )
    end

    it "renders Mustache templates with variables" do
      result = prompt.build(name: "Alice", project: "Tradebot")

      expect(result[:messages][0][:content]).to eq("You are a helpful assistant for Tradebot.")
      expect(result[:messages][1][:content]).to eq("Hello, my name is Alice.")
      expect(result[:model]).to eq("claude-sonnet-4")
      expect(result[:temperature]).to eq(0.3)
      expect(result[:max_tokens]).to eq(1024)
    end

    it "raises when no versions exist" do
      empty_prompt = LlmLogs::Prompt.create!(project: "app", slug: "empty", name: "Empty")
      expect { empty_prompt.build }.to raise_error(RuntimeError, /No versions exist/)
    end
  end

  describe "#version" do
    let(:prompt) { LlmLogs::Prompt.create!(project: "app", slug: "greeting", name: "Greeting") }

    it "loads a specific version" do
      prompt.update_content!(messages: [{ "role" => "user", "content" => "v1" }])
      prompt.update_content!(messages: [{ "role" => "user", "content" => "v2" }])

      v1 = prompt.version(1)
      expect(v1.messages.first["content"]).to eq("v1")
    end
  end

  describe "#rollback_to!" do
    let(:prompt) { LlmLogs::Prompt.create!(project: "app", slug: "greeting", name: "Greeting") }

    it "creates a new version copying content from the specified version" do
      prompt.update_content!(messages: [{ "role" => "user", "content" => "v1" }], model: "gpt-4")
      prompt.update_content!(messages: [{ "role" => "user", "content" => "v2" }], model: "gpt-4o")
      prompt.rollback_to!(1)

      expect(prompt.versions.count).to eq(3)
      current = prompt.current_version
      expect(current.version_number).to eq(3)
      expect(current.messages.first["content"]).to eq("v1")
      expect(current.model).to eq("gpt-4")
      expect(current.changelog).to eq("Rollback to version 1")
    end
  end
end
