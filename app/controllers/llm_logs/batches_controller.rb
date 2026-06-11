module LlmLogs
  class BatchesController < ApplicationController
    def index
      @batches = Batch.recent
      @batches = @batches.where(purpose: params[:purpose]) if params[:purpose].present?
      @batches = @batches.where(status: params[:status]) if params[:status].present?
      @batches = @batches.page(params[:page]).per(50)
    end

    def show
      @batch = Batch.find(params[:id])
      @requests = @batch.requests.order(:created_at).page(params[:page]).per(100)
    end
  end
end
