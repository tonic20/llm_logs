class AddTagsToPrompts < ActiveRecord::Migration[8.0]
  def change
    add_column :llm_logs_prompts, :tags, :string, array: true, default: [], null: false
    add_index :llm_logs_prompts, :tags, using: :gin, name: "index_llm_logs_prompts_on_tags"
  end
end
