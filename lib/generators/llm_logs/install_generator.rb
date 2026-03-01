module LlmLogs
  class InstallGenerator < Rails::Generators::Base
    source_root File.expand_path("templates", __dir__)

    def copy_initializer
      template "initializer.rb", "config/initializers/llm_logs.rb"
    end

    def mount_engine
      route 'mount LlmLogs::Engine, at: "/llm_logs"'
    end

    def copy_migrations
      rake "llm_logs:install:migrations"
    end
  end
end
