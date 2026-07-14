module LlmLogs
  class Batch
    module Adapters
      # Wraps ruby_llm-responses_api's OpenAI Batch API. Contains the remote-API logic
      # previously inline in Submitter/Reconciler; the DB/claim lifecycle stays in those.
      class OpenaiResponses
        PROVIDER = :openai_responses

        def submit(_batch, requests)
          rubyllm_batch = RubyLLM.batch(model: requests.first.model, provider: PROVIDER)
          requests.each do |request|
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
          {provider_batch_id: rubyllm_batch.id, openai_batch_id: rubyllm_batch.id, provider_metadata: {}}
        end

        def terminal_status(batch)
          resume(batch).status
        end

        def results(batch)
          resume(batch).results
        end

        def error_ids(batch)
          resume(batch).errors.filter_map { |e| e["custom_id"] }
        end

        private

        # No memoization: LlmLogs.batch_adapters holds one shared instance of this adapter
        # for the life of the process, so caching the resumed handle here would go stale
        # for a long-running PollJob worker (in-progress batches would never re-fetch a
        # later terminal status) and would grow unbounded. Build a fresh handle every call.
        def resume(batch)
          RubyLLM.batch(id: batch.provider_batch_id, provider: PROVIDER)
        end

        def schema_extra(schema)
          format = SchemaFormat.call(schema)
          format ? {text: format} : {}
        end
      end
    end
  end
end
