class CreateLlmLogsBatchRequests < ActiveRecord::Migration[8.0]
  def change
    create_table :llm_logs_batch_requests do |t|
      t.references :batch, foreign_key: { to_table: :llm_logs_batches }
      t.string :custom_id, null: false
      t.string :purpose, null: false
      t.string :status, null: false, default: "pending"
      t.string :model, null: false
      t.jsonb :payload, null: false, default: {}
      t.jsonb :routing, null: false, default: {}
      t.text :result_content
      t.integer :input_tokens
      t.integer :output_tokens
      t.decimal :cost, precision: 10, scale: 6
      t.bigint :trace_id
      t.text :error
      t.timestamps
    end
    add_index :llm_logs_batch_requests, :custom_id, unique: true
    add_index :llm_logs_batch_requests, [:purpose, :status]
  end
end
