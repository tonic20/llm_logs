Rails.application.routes.draw do
  mount LlmLogs::Engine, at: "/llm_logs"
end
