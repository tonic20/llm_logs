module LlmLogs
  class Batch
    # Maps a batch purpose (e.g. "chat_summary") to a handler object. Handlers respond
    # to `call(request, message)` for successful results and `on_failure(request, error)`
    # for failed/expired requests. The gem owns the lifecycle; the host app owns handlers.
    module HandlerRegistry
      @handlers = {}

      module_function

      def register(purpose, handler)
        @handlers[purpose.to_s] = handler
      end

      def resolve(purpose)
        @handlers[purpose.to_s]
      end

      def clear!
        @handlers = {}
      end
    end
  end
end
