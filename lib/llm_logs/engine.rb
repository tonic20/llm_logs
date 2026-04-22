module LlmLogs
  class Engine < ::Rails::Engine
    isolate_namespace LlmLogs

    initializer "llm_logs.auto_instrument" do
      ActiveSupport.on_load(:active_record) do
        if LlmLogs.auto_instrument && defined?(RubyLLM::Chat)
          require "llm_logs/instrumentation/ruby_llm_chat"
          RubyLLM::Chat.prepend(LlmLogs::Instrumentation::RubyLlmChat)
        end
      end
    end

    rake_tasks do
      load File.expand_path("../tasks/llm_logs.rake", __dir__)
    end
  end
end
