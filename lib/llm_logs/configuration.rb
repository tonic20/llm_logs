module LlmLogs
  class Configuration
    attr_accessor :prompts_source_path, :prompt_subfolders

    def initialize
      @prompts_source_path = nil
      @prompt_subfolders   = %w[skills fragments templates]
    end
  end

  def self.configuration
    @configuration ||= Configuration.new
  end

  def self.configure
    yield(configuration)
  end
end
