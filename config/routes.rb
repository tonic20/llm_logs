LlmLogs::Engine.routes.draw do
  root to: "traces#index"

  resources :traces, only: [:index, :show] do
    resources :spans, only: [:show]
  end

  resources :prompts do
    resources :versions, only: [:index, :show, :destroy], controller: "prompt_versions" do
      member do
        post :restore
      end
      collection do
        get :compare
      end
    end
  end
end
