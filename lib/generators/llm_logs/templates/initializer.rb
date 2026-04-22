LlmLogs.setup do |config|
  # Set to false to disable auto-instrumentation of ruby_llm
  # config.auto_instrument = false

  # Set to false to completely disable logging
  # config.enabled = false

  # Number of days to keep trace data (for future cleanup job)
  # config.retention_days = 30

  # Directory used by `bin/rails llm_logs:prompts:sync`
  # config.prompts_source_path = Rails.root.join("db/data/prompts")

  # Subdirectories to sync within `prompts_source_path`
  # config.prompt_subfolders = %w[skills fragments templates]
end
