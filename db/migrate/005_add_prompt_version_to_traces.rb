class AddPromptVersionToTraces < ActiveRecord::Migration[8.0]
  def change
    add_reference :llm_logs_traces, :prompt_version,
      foreign_key: { to_table: :llm_logs_prompt_versions, on_delete: :nullify },
      null: true
  end
end
