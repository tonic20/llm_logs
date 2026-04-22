namespace :llm_logs do
  namespace :prompts do
    desc "Sync LlmLogs::Prompt records from files in LlmLogs.configuration.prompts_source_path"
    task sync: :environment do
      path = LlmLogs.configuration.prompts_source_path
      raise "LlmLogs.configuration.prompts_source_path is not set" unless path

      LlmLogs::PromptSyncer.sync_all(
        root: path,
        subfolders: LlmLogs.configuration.prompt_subfolders
      )
    end
  end
end
