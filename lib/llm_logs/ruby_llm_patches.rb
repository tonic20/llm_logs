require "llm_logs/ruby_llm_patches/bedrock_sigv4"
require "llm_logs/ruby_llm_patches/converse_openai_reasoning"
require "llm_logs/ruby_llm_patches/converse_foreign_reasoning"
require "llm_logs/ruby_llm_patches/retry_ssl_error"

module LlmLogs
  # Bedrock fixes that upstream ruby_llm 2.0.0 lacks, applied with Module#prepend.
  # Each was verified against 2.0.x only: on 1.x they are skipped (different internals),
  # on a newer ruby_llm they still install but log a warning so we re-check whether
  # upstream fixed the bug (then drop the patch) or moved the method (then the patch
  # skips itself and logs why).
  module RubyLLMPatches
    PATCHES = [BedrockSigV4, ConverseOpenAIReasoning, ConverseForeignReasoning, RetrySSLError].freeze
    MINIMUM = Gem::Version.new("2.0.0")
    VERIFIED = Gem::Requirement.new(">= 2.0.0", "< 2.1")

    module_function

    def install!
      version = Gem::Version.new(RubyLLM::VERSION)
      return [] if version < MINIMUM

      unless VERIFIED.satisfied_by?(version)
        warn_log("verified against ruby_llm #{VERIFIED}, running #{version}: check whether upstream " \
                 "now fixes #{PATCHES.map(&:name).join(', ')} and drop the patches it does")
      end
      PATCHES.select(&:install!)
    end

    def warn_log(message)
      logger = defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger
      logger ? logger.warn("[llm_logs] #{message}") : Kernel.warn("[llm_logs] #{message}")
    end

    # Prepends +patch+ to +target+ when +target+ still defines every method in +methods+.
    def prepend_checked(target, patch, methods)
      return true if target <= patch

      missing = methods.reject { |name| target.method_defined?(name) || target.private_method_defined?(name) }
      if missing.any?
        warn_log("#{patch.name} not installed: #{target} no longer defines #{missing.join(', ')}")
        return false
      end

      target.prepend(patch)
      true
    end
  end
end
