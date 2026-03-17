class CreateLlmLogsPrompts < ActiveRecord::Migration[8.0]
  def change
    create_table :llm_logs_prompts do |t|
      t.string :slug, null: false
      t.string :name, null: false
      t.text :description

      t.timestamps
    end

    add_index :llm_logs_prompts, :slug, unique: true
  end
end
