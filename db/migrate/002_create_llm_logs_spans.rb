class CreateLlmLogsSpans < ActiveRecord::Migration[8.0]
  def change
    create_table :llm_logs_spans do |t|
      t.references :trace, null: false, foreign_key: { to_table: :llm_logs_traces }
      t.bigint :parent_span_id
      t.string :name, null: false
      t.string :span_type, null: false
      t.string :model
      t.string :provider
      t.jsonb :input
      t.jsonb :output
      t.integer :input_tokens
      t.integer :output_tokens
      t.integer :cached_tokens
      t.decimal :cost, precision: 10, scale: 6
      t.float :duration_ms
      t.string :status, null: false, default: "ok"
      t.text :error_message
      t.jsonb :metadata, default: {}
      t.datetime :started_at, null: false
      t.datetime :completed_at

      t.timestamps
    end

    add_foreign_key :llm_logs_spans, :llm_logs_spans, column: :parent_span_id
    add_index :llm_logs_spans, :parent_span_id
    add_index :llm_logs_spans, :span_type
    add_index :llm_logs_spans, :started_at
  end
end
