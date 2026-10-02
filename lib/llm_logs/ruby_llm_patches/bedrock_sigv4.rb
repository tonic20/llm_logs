require "faraday"

module LlmLogs
  module RubyLLMPatches
    # Signs every Bedrock attempt when it is sent.
    #
    # ruby_llm 2.0.0 signs inside the request block (Protocols::Converse#signed_post,
    # Converse::Streaming#stream_response, InvokeModel, Mantle, Guardrails, Rerank, ...),
    # i.e. once, before Faraday's retry middleware runs. A retry after a long timeout
    # (request_timeout 300s vs SigV4's 5-minute window) then replays an expired
    # X-Amz-Date/Authorization and AWS answers 403 "Signature expired", which is not retried.
    #
    # This adds a middleware innermost in every Bedrock Transport::Connection stack (after
    # :retry and after the :json encoder), so each attempt is re-signed over the exact body
    # bytes being sent, at send time. It only touches requests that already carry a SigV4
    # Authorization header and keeps the signing service named in it (bedrock,
    # bedrock-mantle, ...). Auth#signed_get/#signed_post (model listing, batch control
    # endpoints) use Connection.basic, which has no retry, so they need no change.
    module BedrockSigV4
      class Middleware < Faraday::Middleware
        CREDENTIAL = %r{\AAWS4-HMAC-SHA256 Credential=[^/]+/\d{8}/[^/]+/(?<service>[^/]+)/aws4_request}

        def initialize(app, provider:)
          super(app)
          @provider = provider
        end

        def call(env)
          resign(env)
          @app.call(env)
        end

        private

        def resign(env)
          match = CREDENTIAL.match(env.request_headers["Authorization"].to_s)
          return unless match

          body = env.body.nil? ? "" : env.body
          return unless body.is_a?(String) # multipart/IO bodies keep the original signature

          url = env.url
          path = url.query ? "#{url.path}?#{url.query}" : url.path
          headers = @provider.sign_headers(
            env.method.to_s.upcase, path, body,
            base_url: "#{url.scheme}://#{url.host}", service: match[:service]
          )
          env.request_headers.delete("X-Amz-Security-Token") # credentials may have rotated
          env.request_headers.merge!(headers.except("Content-Type"))
        end
      end

      module ConnectionPatch
        private

        def setup_middleware(faraday)
          super
          faraday.use(Middleware, provider: @provider) if BedrockSigV4.bedrock?(@provider)
        end
      end

      module_function

      def bedrock?(provider)
        defined?(RubyLLM::Providers::Bedrock) && provider.is_a?(RubyLLM::Providers::Bedrock) &&
          provider.respond_to?(:sign_headers)
      end

      def install!
        RubyLLMPatches.prepend_checked(RubyLLM::Transport::Connection, ConnectionPatch, %i[setup_middleware])
      end
    end
  end
end
