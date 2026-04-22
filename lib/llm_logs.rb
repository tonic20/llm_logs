require "kaminari"
require "llm_logs/version"
require "llm_logs/configuration"
require "llm_logs/engine"
require "llm_logs/tracer"
require "llm_logs/prompt_renderer"

module LlmLogs
  def self.setup
    yield configuration
  end

  def self.enabled?
    enabled
  end

  def self.enabled
    configuration.enabled
  end

  def self.enabled=(enabled)
    configuration.enabled = enabled
  end

  def self.auto_instrument
    configuration.auto_instrument
  end

  def self.auto_instrument=(auto_instrument)
    configuration.auto_instrument = auto_instrument
  end

  def self.retention_days
    configuration.retention_days
  end

  def self.retention_days=(retention_days)
    configuration.retention_days = retention_days
  end

  def self.trace(name, **options, &block)
    LlmLogs::Tracer.start_trace(name, **options, &block)
  end
end
