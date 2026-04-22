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
    end

    expect(LlmLogs.enabled).to eq(false)
    expect(LlmLogs.enabled?).to eq(false)
    expect(LlmLogs.auto_instrument).to eq(false)
    expect(LlmLogs.retention_days).to eq(90)
    expect(LlmLogs.configuration.prompts_source_path).to eq("db/data/prompts")
    expect(LlmLogs.configuration.prompt_subfolders).to eq(%w[agents fragments])
  end

  it "does not expose a separate configure entrypoint" do
    expect(LlmLogs).not_to respond_to(:configure)
  end
end
