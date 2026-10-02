require "faraday"

module LlmLogs
  module RubyLLMPatches
    # Retries TLS handshake failures (Faraday::SSLError, e.g. "SSL_connect ... unexpected
    # eof"). faraday-net_http wraps every OpenSSL::SSL::SSLError as Faraday::SSLError, including
    # read errors after the request was written, so this is the same trade-off ruby_llm
    # already accepts for read timeouts. ruby_llm's retry_if (transport/connection.rb) still
    # refuses non-idempotent requests and streams that already delivered content.
    # Faraday::SSLError is not a Faraday::ConnectionFailed, so 2.0.0's retry list misses it.
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
