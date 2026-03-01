class RemoveProjectFromLlmLogs < ActiveRecord::Migration[8.0]
  def change
    remove_index :llm_logs_traces, :project
    remove_column :llm_logs_traces, :project, :string

    remove_index :llm_logs_prompts, [:project, :slug]
    remove_column :llm_logs_prompts, :project, :string, null: false
    add_index :llm_logs_prompts, :slug, unique: true
  end
end
