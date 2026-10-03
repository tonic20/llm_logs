module LlmLogs
  class Engine < ::Rails::Engine
    isolate_namespace LlmLogs

    initializer "llm_logs.auto_instrument" do
      ActiveSupport.on_load(:active_record) do
        if LlmLogs.auto_instrument && defined?(RubyLLM::Chat)
          require "llm_logs/instrumentation/ruby_llm_chat"
          LlmLogs::Instrumentation::RubyLlmChat.install!
        end
      end
    end

    # Bedrock fixes missing from upstream ruby_llm 2.0.0. Installed whether or not
    # auto-instrumentation is on: they change request behaviour, not logging.
    initializer "llm_logs.ruby_llm_patches" do
      if defined?(RubyLLM::VERSION)
        require "llm_logs/ruby_llm_patches"
        LlmLogs::RubyLLMPatches.install!
      end
    end

    rake_tasks do
      load File.expand_path("../tasks/llm_logs.rake", __dir__)
    end
  end
end
