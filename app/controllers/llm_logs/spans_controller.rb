module LlmLogs
  class SpansController < ApplicationController
    def show
      @trace = Trace.find(params[:trace_id])
      @span = @trace.spans.find(params[:id])
      @input = @span.full_input
    end
  end
end
