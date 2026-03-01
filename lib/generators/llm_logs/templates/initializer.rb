LlmLogs.setup do |config|
  # Project name used as default for traces and prompts
  config.default_project = "my_app"

  # Set to false to disable auto-instrumentation of ruby_llm
  # config.auto_instrument = false

  # Set to false to completely disable logging
  # config.enabled = false

  # Number of days to keep trace data (for future cleanup job)
  # config.retention_days = 30
end
