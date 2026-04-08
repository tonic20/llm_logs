module LlmLogs
  class TracesController < ApplicationController
    def index
      @traces = Trace.recent
      @traces = @traces.by_status(params[:status]) if params[:status].present?
      if params[:prompt_version_id].present?
        @traces = @traces.where(prompt_version_id: params[:prompt_version_id])
        @filter_version = PromptVersion.find_by(id: params[:prompt_version_id])
      end
      @traces = @traces.page(params[:page]).per(50)
    end

    def show
      @trace = Trace.includes(prompt_version: :prompt).find(params[:id])
      @root_spans = @trace.root_spans
    end

  end
end
