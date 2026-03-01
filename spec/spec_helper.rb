ENV["RAILS_ENV"] = "test"

require_relative "dummy/config/environment"

require "rspec/rails"

# Migrations are run manually before specs; skip maintain_test_schema
# ActiveRecord::Migration.maintain_test_schema!

RSpec.configure do |config|
  config.use_transactional_fixtures = true
  config.infer_spec_type_from_file_location!
  config.filter_rails_from_backtrace!
end
