require "llm_logs/version"
require "llm_logs/engine"
require "llm_logs/tracer"
require "llm_logs/prompt_renderer"

module LlmLogs
  mattr_accessor :enabled, default: true
  mattr_accessor :default_project, default: "default"
  mattr_accessor :auto_instrument, default: true
  mattr_accessor :retention_days, default: 30

  def self.setup
    yield self
  end

  def self.trace(name, **options, &block)
    LlmLogs::Tracer.start_trace(name, **options, &block)
  end
end
