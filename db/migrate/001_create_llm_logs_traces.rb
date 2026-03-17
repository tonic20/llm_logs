class CreateLlmLogsTraces < ActiveRecord::Migration[8.0]
  def change
    create_table :llm_logs_traces do |t|
      t.string :name, null: false
      t.string :status, null: false, default: "running"
      t.jsonb :metadata, default: {}
      t.integer :total_input_tokens, default: 0
      t.integer :total_output_tokens, default: 0
      t.integer :total_cached_tokens, default: 0, null: false
      t.decimal :total_cost, precision: 10, scale: 6, default: 0
      t.float :duration_ms
      t.integer :spans_count, default: 0, null: false
      t.datetime :started_at, null: false
      t.datetime :completed_at

      t.timestamps
    end

    add_index :llm_logs_traces, :status
    add_index :llm_logs_traces, :started_at
  end
end
