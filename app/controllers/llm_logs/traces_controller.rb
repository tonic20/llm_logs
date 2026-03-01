module LlmLogs
  class TracesController < ApplicationController
    def index
      @traces = Trace.recent
      @traces = @traces.by_status(params[:status]) if params[:status].present?
      @traces = @traces.limit(params.fetch(:limit, 50).to_i).offset(params.fetch(:offset, 0).to_i)
    end

    def show
      @trace = Trace.find(params[:id])
      @root_spans = @trace.root_spans
    end

  end
end
