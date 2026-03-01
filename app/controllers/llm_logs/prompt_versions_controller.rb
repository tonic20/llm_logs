module LlmLogs
  class PromptVersionsController < ApplicationController
    def index
      @prompt = Prompt.find(params[:prompt_id])
      @versions = @prompt.versions.order(version_number: :desc)
    end

    def show
      @prompt = Prompt.find(params[:prompt_id])
      @version = @prompt.versions.find(params[:id])
    end
  end
end
