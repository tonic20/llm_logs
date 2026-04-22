require "spec_helper"

RSpec.describe LlmLogs::Prompt do
  describe "validations" do
    it "requires slug and name" do
      prompt = LlmLogs::Prompt.new
      expect(prompt).not_to be_valid
      expect(prompt.errors[:slug]).to include("can't be blank")
      expect(prompt.errors[:name]).to include("can't be blank")
    end

    it "enforces unique slug" do
      LlmLogs::Prompt.create!(slug: "greeting", name: "Greeting")
      dupe = LlmLogs::Prompt.new(slug: "greeting", name: "Other")
      expect(dupe).not_to be_valid
    end
  end

  describe ".load" do
    it "finds prompt by slug" do
      created = LlmLogs::Prompt.create!(slug: "greeting", name: "Greeting")
      loaded = LlmLogs::Prompt.load("greeting")
      expect(loaded).to eq(created)
    end

    it "raises when not found" do
      expect {
        LlmLogs::Prompt.load("missing")
      }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end

  describe "#update_content!" do
    let(:prompt) { LlmLogs::Prompt.create!(slug: "greeting", name: "Greeting") }

    it "creates a new version with incrementing number" do
      prompt.update_content!(messages: [{ "role" => "user", "content" => "Hello {{name}}" }], model: "gpt-4")
      prompt.update_content!(messages: [{ "role" => "user", "content" => "Hi {{name}}" }], model: "gpt-4", changelog: "simplified")

      expect(prompt.versions.count).to eq(2)
      expect(prompt.versions.pluck(:version_number)).to eq([1, 2])
      expect(prompt.current_version.changelog).to eq("simplified")
    end
  end

  describe "#build" do
    let(:prompt) { LlmLogs::Prompt.create!(slug: "greeting", name: "Greeting") }

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
      empty_prompt = LlmLogs::Prompt.create!(slug: "empty", name: "Empty")
      expect { empty_prompt.build }.to raise_error(RuntimeError, /No versions exist/)
    end

    it "auto-captures prompt version on the active trace" do
      trace = nil
      LlmLogs::Tracer.start_trace("test") do |t|
        trace = t
        prompt.build(name: "Alice", project: "Tradebot")
      end

      expect(trace.reload.prompt_version).to eq(prompt.current_version)
    end

    it "does not overwrite prompt_version if already set" do
      other_prompt = LlmLogs::Prompt.create!(slug: "other", name: "Other")
      other_prompt.update_content!(messages: [{ "role" => "user", "content" => "Other" }])
      other_version = other_prompt.current_version

      trace = nil
      LlmLogs::Tracer.start_trace("test") do |t|
        trace = t
        trace.update!(prompt_version: other_version)
        prompt.build(name: "Alice", project: "Tradebot")
      end

      expect(trace.reload.prompt_version).to eq(other_version)
    end

    it "does not fail when no trace is active" do
      Thread.current[:llm_logs_trace] = nil
      result = prompt.build(name: "Alice", project: "Tradebot")
      expect(result[:messages]).to be_present
    end
  end

  describe "#version" do
    let(:prompt) { LlmLogs::Prompt.create!(slug: "greeting", name: "Greeting") }

    it "loads a specific version" do
      prompt.update_content!(messages: [{ "role" => "user", "content" => "v1" }])
      prompt.update_content!(messages: [{ "role" => "user", "content" => "v2" }])

      v1 = prompt.version(1)
      expect(v1.messages.first["content"]).to eq("v1")
    end
  end

  describe "#rollback_to!" do
    let(:prompt) { LlmLogs::Prompt.create!(slug: "greeting", name: "Greeting") }

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

  describe "tag scopes" do
    let!(:skill)    { LlmLogs::Prompt.create!(slug: "strategy-discovery", name: "S", tags: %w[skills]) }
    let!(:fragment) { LlmLogs::Prompt.create!(slug: "discovery-onchain-context", name: "F", tags: %w[fragments on-chain]) }
    let!(:template) { LlmLogs::Prompt.create!(slug: "trading-memo", name: "T", tags: %w[templates]) }

    it ".with_tag returns prompts that contain the tag" do
      expect(LlmLogs::Prompt.with_tag("skills")).to contain_exactly(skill)
      expect(LlmLogs::Prompt.with_tag("on-chain")).to contain_exactly(fragment)
    end

    it ".with_any_tag returns prompts matching any of the given tags" do
      expect(LlmLogs::Prompt.with_any_tag(%w[skills templates]))
        .to contain_exactly(skill, template)
    end

    it "#tags_string joins tags with commas" do
      expect(fragment.tags_string).to eq("fragments, on-chain")
    end
  end
end
