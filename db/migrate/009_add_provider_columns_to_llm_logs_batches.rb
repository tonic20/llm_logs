class AddProviderColumnsToLlmLogsBatches < ActiveRecord::Migration[8.0]
  def change
    add_column :llm_logs_batches, :provider_batch_id, :string
    add_column :llm_logs_batches, :provider_metadata, :jsonb, null: false, default: {}
    add_index  :llm_logs_batches, :provider_batch_id

    # Backfill existing OpenAI rows so the reconciler/poll job can key off the
    # generic column uniformly.
    up_only do
      execute <<~SQL.squish
        UPDATE llm_logs_batches
        SET provider_batch_id = openai_batch_id
        WHERE openai_batch_id IS NOT NULL
      SQL
    end
  end
end
