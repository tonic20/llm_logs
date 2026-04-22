require "spec_helper"
require "fileutils"
require "tmpdir"

RSpec.describe LlmLogs::PromptSyncer do
  around(:each) do |example|
    Dir.mktmpdir("prompt_sync") do |root|
      @root = Pathname.new(root)
      %w[skills fragments templates].each { |sub| (@root / sub).mkpath }
      example.run
    end
  end

  def write(path, contents)
    file = @root / path
    file.parent.mkpath
    file.write(contents)
  end

  def sync!
    LlmLogs::PromptSyncer.sync_all(root: @root, subfolders: %w[skills fragments templates])
  end

  it "creates a prompt from a single-body markdown file" do
    write("skills/backtest-evaluation.md", <<~MD)
      ---
      slug: backtest-evaluation
      name: Backtest Evaluation
      description: How to evaluate backtests
      ---
      Body content here.
    MD

    sync!

    prompt = LlmLogs::Prompt.find_by!(slug: "backtest-evaluation")
    expect(prompt.name).to eq("Backtest Evaluation")
    expect(prompt.description).to eq("How to evaluate backtests")
    expect(prompt.tags).to eq(%w[skills])
    expect(prompt.current_version.messages).to eq([{ "role" => "system", "content" => "Body content here.\n" }])
  end

  it "merges front-matter tags with the subfolder tag and dedupes" do
    write("fragments/discovery-claude-notes.md", <<~MD)
      ---
      slug: discovery-claude-notes
      name: Claude notes
      tags: [provider-notes, claude, fragments]
      ---
      notes
    MD

    sync!

    expect(LlmLogs::Prompt.find_by!(slug: "discovery-claude-notes").tags)
      .to match_array(%w[fragments provider-notes claude])
  end

  it "does not create a new version when content is unchanged" do
    write("skills/foo.md", "---\nslug: foo\nname: F\n---\nsame body\n")
    sync!
    expect { sync! }.not_to change { LlmLogs::Prompt.find_by!(slug: "foo").versions.count }
  end

  it "creates a new version when the body changes" do
    write("skills/foo.md", "---\nslug: foo\nname: F\n---\nv1\n")
    sync!
    write("skills/foo.md", "---\nslug: foo\nname: F\n---\nv2\n")
    sync!
    prompt = LlmLogs::Prompt.find_by!(slug: "foo")
    expect(prompt.versions.count).to eq(2)
    expect(prompt.current_version.messages.first["content"]).to eq("v2\n")
  end

  it "handles multi-message templates with body_file references" do
    write("templates/trading-memo.md", <<~MD)
      ---
      slug: trading-memo
      name: Trading Memo
      model: deepseek/deepseek-v3.2
      model_params:
        temperature: 0.5
      messages:
        - role: system
          body_file: trading_memo_system.md
        - role: user
          body_file: trading_memo_user.md
      ---
    MD
    write("templates/trading_memo_system.md", "system body\n")
    write("templates/trading_memo_user.md",   "user body\n")

    sync!

    prompt = LlmLogs::Prompt.find_by!(slug: "trading-memo")
    version = prompt.current_version
    expect(version.messages).to eq([
      { "role" => "system", "content" => "system body\n" },
      { "role" => "user",   "content" => "user body\n" }
    ])
    expect(version.model).to eq("deepseek/deepseek-v3.2")
    expect(version.model_params).to eq({ "temperature" => 0.5 })
  end

  it "raises when a body_file is missing" do
    write("templates/broken.md", <<~MD)
      ---
      slug: broken
      name: Broken
      messages:
        - role: system
          body_file: does_not_exist.md
      ---
    MD
    expect { sync! }.to raise_error(/body_file.*does_not_exist/)
  end

  it "requires slug and name in front-matter" do
    write("skills/bad.md", "---\nname: Missing Slug\n---\nbody\n")
    expect { sync! }.to raise_error(/slug/)
  end

  it "creates a new version when model_params change" do
    write("templates/foo.md", <<~MD)
      ---
      slug: foo
      name: F
      model: gpt-4
      model_params:
        temperature: 0.3
      ---
      body
    MD
    sync!
    write("templates/foo.md", <<~MD)
      ---
      slug: foo
      name: F
      model: gpt-4
      model_params:
        temperature: 0.7
      ---
      body
    MD
    sync!

    prompt = LlmLogs::Prompt.find_by!(slug: "foo")
    expect(prompt.versions.count).to eq(2)
    expect(prompt.current_version.model_params).to eq({ "temperature" => 0.7 })
  end

  it "does not mint a new version when YAML uses symbol keys for model_params" do
    contents = <<~MD
      ---
      slug: foo
      name: F
      model: gpt-4
      model_params:
        :temperature: 0.3
      ---
      body
    MD
    write("templates/foo.md", contents)
    sync!
    write("templates/foo.md", contents)
    expect { sync! }.not_to change { LlmLogs::Prompt.find_by!(slug: "foo").versions.count }
  end

  it "rolls back the prompt when version creation fails" do
    write("skills/boom.md", "---\nslug: boom\nname: B\n---\nbody\n")
    allow_any_instance_of(LlmLogs::Prompt).to receive(:update_content!).and_raise("boom")

    expect { sync! }.to raise_error("boom")
    expect(LlmLogs::Prompt.find_by(slug: "boom")).to be_nil
  end
end
