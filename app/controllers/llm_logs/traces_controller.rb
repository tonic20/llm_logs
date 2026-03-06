module LlmLogs
  class TracesController < ApplicationController
    def index
      @traces = Trace.recent
      @traces = @traces.by_status(params[:status]) if params[:status].present?
      @traces = @traces.page(params[:page]).per(50)
    end

    def show
      @trace = Trace.find(params[:id])
      @root_spans = @trace.root_spans
    end

  end
end
