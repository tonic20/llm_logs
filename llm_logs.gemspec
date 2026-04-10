require_relative "lib/llm_logs/version"

Gem::Specification.new do |spec|
  spec.name        = "llm_logs"
  spec.version     = LlmLogs::VERSION
  spec.authors     = ["Anton"]
  spec.summary     = "Rails engine for LLM logging and prompt management"
  spec.description = "Mountable Rails engine that provides hierarchical LLM call tracing and versioned prompt management with Mustache templates."
  spec.homepage    = "https://github.com/tonic20/llm_logs"
  spec.license     = "MIT"

  spec.metadata["homepage_uri"]      = spec.homepage
  spec.metadata["source_code_uri"]   = spec.homepage
  spec.metadata["changelog_uri"]     = "#{spec.homepage}/blob/main/CHANGELOG.md"

  spec.required_ruby_version = ">= 3.3"

  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    Dir["{app,config,db,lib}/**/*", "Rakefile", "README.md"]
  end

  spec.add_dependency "rails", "~> 8.0"
  spec.add_dependency "mustache", "~> 1.1"
  spec.add_dependency "kaminari", "~> 1.2"
  spec.add_dependency "diffy", "~> 3.4"
end
