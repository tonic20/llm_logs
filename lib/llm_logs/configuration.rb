module LlmLogs
  class Configuration
    BedrockBatch = Struct.new(:role_arn, :s3_bucket, :s3_prefix, :min_records, :model_matcher, :region, keyword_init: true)

    attr_accessor :enabled, :auto_instrument, :retention_days, :prompts_source_path, :prompt_subfolders,
                  :batch_enabled, :page_size, :bedrock_batch, :reasoning_effort_options

    def initialize
      @enabled             = true
      @auto_instrument     = true
      @retention_days      = 30
      @prompts_source_path = nil
      @prompt_subfolders   = %w[skills fragments templates]
      @batch_enabled       = true
      @page_size           = 50
      @bedrock_batch       = nil
      # Effort tiers offered in the prompt form. Union of what current providers
      # accept -- OpenAI takes all six, Anthropic has no "none". Narrow this in an
      # initializer if your app targets one provider.
      @reasoning_effort_options = %w[none low medium high xhigh max]
    end
  end

  def self.configuration
    @configuration ||= Configuration.new
  end
end
