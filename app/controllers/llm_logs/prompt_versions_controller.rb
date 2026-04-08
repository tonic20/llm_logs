require "diffy"

module LlmLogs
  class PromptVersionsController < ApplicationController
    before_action :set_prompt

    def index
      @versions = @prompt.versions.order(version_number: :desc)
    end

    def show
      @version = @prompt.versions.find(params[:id])
    end

    def restore
      version = @prompt.versions.find(params[:id])
      @prompt.rollback_to!(version.version_number)
      redirect_to prompt_path(@prompt), notice: "Restored to version #{version.version_number}."
    end

    def destroy
      version = @prompt.versions.find(params[:id])

      if version == @prompt.current_version
        redirect_to prompt_versions_path(@prompt), alert: "Cannot delete the current active version."
        return
      end

      version.destroy!
      redirect_to prompt_versions_path(@prompt), notice: "Version #{version.version_number} deleted."
    end

    def compare

      if params[:a].blank? || params[:b].blank? || params[:a] == params[:b]
        redirect_to prompt_versions_path(@prompt), alert: "Select two different versions to compare."
        return
      end

      @version_a = @prompt.versions.find_by(version_number: params[:a])
      @version_b = @prompt.versions.find_by(version_number: params[:b])

      unless @version_a && @version_b
        redirect_to prompt_versions_path(@prompt), alert: "Version not found."
        return
      end

      max_messages = [@version_a.messages.size, @version_b.messages.size].max
      @diffs = (0...max_messages).map do |i|
        msg_a = @version_a.messages[i]
        msg_b = @version_b.messages[i]
        role = (msg_a || msg_b)["role"]
        content_a = ERB::Util.html_escape(msg_a&.dig("content") || "")
        content_b = ERB::Util.html_escape(msg_b&.dig("content") || "")
        diff_html = Diffy::SplitDiff.new(content_a, content_b, format: :html_simple)
        { role: role, left: diff_html.left, right: diff_html.right }
      end
    end

    private

    def set_prompt
      @prompt = Prompt.find(params[:prompt_id])
    end
  end
end
