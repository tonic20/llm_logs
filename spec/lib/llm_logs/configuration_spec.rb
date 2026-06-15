require "spec_helper"

RSpec.describe LlmLogs::Configuration do
  around do |example|
    original_configuration = LlmLogs.configuration
    LlmLogs.instance_variable_set(:@configuration, described_class.new)

    example.run
  ensure
    LlmLogs.instance_variable_set(:@configuration, original_configuration)
  end

  it "configures every setting through setup" do
    LlmLogs.setup do |config|
      config.enabled = false
      config.auto_instrument = false
      config.retention_days = 90
      config.prompts_source_path = "db/data/prompts"
      config.prompt_subfolders = %w[agents fragments]
      config.traces_page_size = 20
    end

    expect(LlmLogs.enabled).to eq(false)
    expect(LlmLogs.enabled?).to eq(false)
    expect(LlmLogs.auto_instrument).to eq(false)
    expect(LlmLogs.retention_days).to eq(90)
    expect(LlmLogs.configuration.prompts_source_path).to eq("db/data/prompts")
    expect(LlmLogs.configuration.prompt_subfolders).to eq(%w[agents fragments])
    expect(LlmLogs.traces_page_size).to eq(20)
  end

  it "defaults the traces page size to 50" do
    expect(LlmLogs::Configuration.new.traces_page_size).to eq(50)
    expect(LlmLogs.traces_page_size).to eq(50)
  end

  it "does not expose a separate configure entrypoint" do
    expect(LlmLogs).not_to respond_to(:configure)
  end

  it "enables batching by default and exposes the provider" do
    config = LlmLogs::Configuration.new
    expect(config.batch_enabled).to be(true)
    expect(config.batch_provider).to eq(:openai_responses)
  end

  it "exposes batch_enabled? at the module level" do
    LlmLogs.configuration.batch_enabled = false
    expect(LlmLogs.batch_enabled?).to be(false)
  ensure
    LlmLogs.configuration.batch_enabled = true
  end
end
