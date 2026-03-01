module LlmLogs
  class SpansController < ApplicationController
    def show
      @trace = Trace.find(params[:trace_id])
      @span = @trace.spans.find(params[:id])
    end
  end
end
