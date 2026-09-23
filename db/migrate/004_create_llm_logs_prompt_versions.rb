class CreateLlmLogsPromptVersions < ActiveRecord::Migration[8.0]
  def change
    create_table :llm_logs_prompt_versions do |t|
      t.references :prompt, null: false, foreign_key: { to_table: :llm_logs_prompts }
      t.integer :version_number, null: false
      t.column :messages, (connection.adapter_name == "PostgreSQL" ? :jsonb : :json), null: false, default: []
      t.string :model
      t.column :model_params, (connection.adapter_name == "PostgreSQL" ? :jsonb : :json), default: {}
      t.column :default_variables, (connection.adapter_name == "PostgreSQL" ? :jsonb : :json), default: {}
      t.text :changelog

      t.timestamps
    end

    add_index :llm_logs_prompt_versions, [:prompt_id, :version_number], unique: true,
      name: "idx_llm_logs_prompt_versions_on_prompt_and_version"
  end
end
