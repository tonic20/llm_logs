ENV["RAILS_ENV"] = "test"

require_relative "dummy/config/environment"

require "rspec/rails"
require "ruby_llm"
require "webmock/rspec"

require "llm_logs/instrumentation/ruby_llm_chat"
RubyLLM.configure { |c| c.openai_api_key = "test-key" }
# The dummy app does not Bundler.require ruby_llm (a development dependency), so the
# engine initializer skips it at boot; install explicitly (it is idempotent).
LlmLogs::Instrumentation::RubyLlmChat.install!
WebMock.disable_net_connect!(allow_localhost: true)

if ENV["LLM_LOGS_DATABASE"] == "sqlite"
  ActiveRecord::MigrationContext.new(File.expand_path("../db/migrate", __dir__)).migrate
end

# Migrations are run manually before specs; skip maintain_test_schema
# ActiveRecord::Migration.maintain_test_schema!

RSpec.configure do |config|
  config.filter_run_excluding postgresql: true if ENV["LLM_LOGS_DATABASE"] == "sqlite"
  config.use_transactional_fixtures = true
  config.infer_spec_type_from_file_location!
  config.filter_rails_from_backtrace!
end
