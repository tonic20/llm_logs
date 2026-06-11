class CreateLlmLogsBatches < ActiveRecord::Migration[8.0]
  def change
    create_table :llm_logs_batches do |t|
      t.string :purpose, null: false
      t.string :provider, null: false, default: "openai_responses"
      t.string :model, null: false
      t.string :openai_batch_id
      t.string :openai_output_file_id
      t.string :openai_error_file_id
      t.string :status, null: false, default: "pending"
      t.integer :request_count, null: false, default: 0
      t.jsonb :metadata, null: false, default: {}
      t.datetime :submitted_at
      t.datetime :completed_at
      t.datetime :reconciled_at
      t.timestamps
    end
    add_index :llm_logs_batches, :openai_batch_id, unique: true
    add_index :llm_logs_batches, :status
    add_index :llm_logs_batches, :purpose
  end
end
