class CreateLlmLogsPromptVersions < ActiveRecord::Migration[8.0]
  def change
    create_table :llm_logs_prompt_versions do |t|
      t.references :prompt, null: false, foreign_key: { to_table: :llm_logs_prompts }
      t.integer :version_number, null: false
      t.jsonb :messages, null: false, default: []
      t.string :model
      t.jsonb :model_params, default: {}
      t.jsonb :default_variables, default: {}
      t.text :changelog

      t.timestamps
    end

    add_index :llm_logs_prompt_versions, [:prompt_id, :version_number], unique: true,
      name: "idx_llm_logs_prompt_versions_on_prompt_and_version"
  end
end
