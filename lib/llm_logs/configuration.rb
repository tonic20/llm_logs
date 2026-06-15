module LlmLogs
  class Configuration
    attr_accessor :enabled, :auto_instrument, :retention_days, :prompts_source_path, :prompt_subfolders,
                  :batch_enabled, :batch_provider, :traces_page_size

    def initialize
      @enabled             = true
      @auto_instrument     = true
      @retention_days      = 30
      @prompts_source_path = nil
      @prompt_subfolders   = %w[skills fragments templates]
      @batch_enabled       = true
      @batch_provider      = :openai_responses
      @traces_page_size    = 50
    end
  end

  def self.configuration
    @configuration ||= Configuration.new
  end
end
