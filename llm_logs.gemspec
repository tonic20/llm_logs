require_relative "lib/llm_logs/version"

Gem::Specification.new do |spec|
  spec.name        = "llm_logs"
  spec.version     = LlmLogs::VERSION
  spec.authors     = ["Anton"]
  spec.summary     = "Rails engine for LLM logging and prompt management"
  spec.description = "Mountable Rails engine that provides hierarchical LLM call tracing and versioned prompt management with Mustache templates."
  spec.license     = "MIT"

  spec.required_ruby_version = ">= 3.3"

  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    Dir["{app,config,db,lib}/**/*", "Rakefile", "README.md"]
  end

  spec.add_dependency "rails", ">= 8.0"
  spec.add_dependency "mustache", "~> 1.1"
end
