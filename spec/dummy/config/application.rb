require_relative "boot"
require "rails/all"

Bundler.require(*Rails.groups)
require "llm_logs"

module Dummy
  class Application < Rails::Application
    config.load_defaults Rails::VERSION::STRING.to_f
    config.eager_load = false
    config.root = File.expand_path("../..", __FILE__)
    config.secret_key_base = "test_secret_key_base_for_llm_logs_dummy_app"
  end
end
