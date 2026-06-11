module LlmLogs
  class Batch
    # Groups pending BatchRequests of one purpose+model into a single OpenAI batch via
    # ruby_llm-responses_api. To prevent two concurrent FlushJobs from double-submitting
    # the same requests, it first CLAIMS the pending rows in a `FOR UPDATE SKIP LOCKED`
    # transaction (assigning them to a placeholder Batch with no openai_batch_id, which
    # flips them out of the `pending` scope and which PollJob ignores). It then submits to
    # OpenAI and records the batch id. If submission fails, the claim is released (requests
    # return to `pending`) and the placeholder batch is dropped, so the work retries next flush.
    class Submitter
      def initialize(purpose:, model:, metadata: {})
        @purpose = purpose
        @model = model
        @metadata = metadata
      end

      def call
        batch = claim_batch
        return nil if batch.nil?

        submit(batch)
        batch
      end

      private

      def claim_batch
        BatchRequest.transaction do
          requests = BatchRequest.pending
            .where(purpose: @purpose, model: @model)
            .lock("FOR UPDATE SKIP LOCKED")
            .to_a
          next nil if requests.empty?

          batch = LlmLogs::Batch.create!(
            purpose: @purpose,
            provider: LlmLogs.batch_provider.to_s,
            model: @model,
            status: :pending,
            request_count: requests.size,
            metadata: @metadata
          )
          BatchRequest.where(id: requests.map(&:id)).update_all(batch_id: batch.id, status: :submitted)
          batch
        end
      end

      def submit(batch)
        rubyllm_batch = RubyLLM.batch(model: @model, provider: LlmLogs.batch_provider)
        batch.requests.each do |request|
          payload = request.payload
          rubyllm_batch.add(
            payload["input"],
            id: request.custom_id,
            instructions: payload["instructions"],
            temperature: payload["temperature"],
            **schema_extra(payload["schema"])
          )
        end
        rubyllm_batch.create!
        batch.update!(openai_batch_id: rubyllm_batch.id, status: :submitted, submitted_at: Time.current)
      rescue StandardError
        # Release the claim so the requests retry on the next flush, and drop the
        # placeholder batch so it isn't polled. Re-raise so the caller/job sees the error.
        batch.requests.update_all(batch_id: nil, status: :pending)
        batch.destroy
        raise
      end

      def schema_extra(schema)
        format = SchemaFormat.call(schema)
        format ? { text: format } : {}
      end
    end
  end
end
