module LlmLogs
  class TracesController < ApplicationController
    def index
      @traces = Trace.recent
      @traces = @traces.by_project(params[:project]) if params[:project].present?
      @traces = @traces.by_status(params[:status]) if params[:status].present?
      @traces = @traces.limit(params.fetch(:limit, 50).to_i).offset(params.fetch(:offset, 0).to_i)

      @projects = Trace.distinct.pluck(:project).compact.sort
    end

    def show
      @trace = Trace.find(params[:id])
      @root_spans = @trace.root_spans
    end

    def destroy
      @trace = Trace.find(params[:id])
      @trace.destroy
      redirect_to traces_path, notice: "Trace deleted."
    end
  end
end
