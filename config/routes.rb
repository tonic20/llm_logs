LlmLogs::Engine.routes.draw do
  root to: "traces#index"

  resources :traces, only: [:index, :show, :destroy] do
    resources :spans, only: [:show]
  end

  resources :prompts do
    resources :versions, only: [:index, :show], controller: "prompt_versions"
  end
end
