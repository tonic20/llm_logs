require "faraday"

module LlmLogs
  module RubyLLMPatches
    # Retries TLS handshake failures (Faraday::SSLError, e.g. "SSL_connect ... unexpected
    # eof"). They happen before the request body is sent, so a retry cannot double-submit;
    # ruby_llm's usage ledger already books them as never sent. Faraday::SSLError is not a
    # Faraday::ConnectionFailed, so 2.0.0's retry list misses it.
    module RetrySSLError
      private

      def retry_exceptions
        exceptions = super
        exceptions.include?(Faraday::SSLError) ? exceptions : exceptions + [Faraday::SSLError]
      end

      def self.install!
        RubyLLMPatches.prepend_checked(RubyLLM::Transport::Connection, self, %i[retry_exceptions])
      end
    end
  end
end
