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

    def restore
      @prompt = Prompt.find(params[:prompt_id])
      version = @prompt.versions.find(params[:id])
      @prompt.rollback_to!(version.version_number)
      redirect_to prompt_path(@prompt), notice: "Restored to version #{version.version_number}."
    end

    def destroy
      @prompt = Prompt.find(params[:prompt_id])
      version = @prompt.versions.find(params[:id])

      if version == @prompt.current_version
        redirect_to prompt_versions_path(@prompt), alert: "Cannot delete the current active version."
        return
      end

      version.destroy!
      redirect_to prompt_versions_path(@prompt), notice: "Version #{version.version_number} deleted."
    end
  end
end
