module LlmLogs
  module Tracer
    # Trace/span context is kept in Fiber-local storage (Fiber[]), which child
    # fibers inherit on creation. This matters for fiber-based schedulers such as
    # socketry/async: work driven inside a child fiber still sees the active
    # trace. The legacy Thread.current[:key] store is *not* inherited by child
    # fibers, which caused spans to auto-create orphan traces instead of nesting.
    def self.current_trace
      Fiber[:llm_logs_trace]
    end

    def self.current_span
      Fiber[:llm_logs_span]
    end

    def self.current_span=(span)
      Fiber[:llm_logs_span] = span
    end

    def self.start_trace(name, metadata: {})
      trace = LlmLogs::Trace.create!(
        name: name,
        status: "running",
        metadata: metadata,
        started_at: Time.current
      )

      previous_trace = Fiber[:llm_logs_trace]
      previous_span = Fiber[:llm_logs_span]
      Fiber[:llm_logs_trace] = trace
      Fiber[:llm_logs_span] = nil

      begin
        yield trace
      rescue => e
        trace.fail!
        raise
      ensure
        trace.complete! if trace.status == "running"
        Fiber[:llm_logs_trace] = previous_trace
        Fiber[:llm_logs_span] = previous_span
      end
    end

    def self.start_span(name:, span_type:, model: nil, provider: nil, input: nil, metadata: {})
      trace = current_trace || auto_create_trace(name)
      parent = current_span

      span = LlmLogs::Span.create!(
        trace: trace,
        parent_span: parent,
        name: name,
        span_type: span_type,
        model: model,
        provider: provider,
        input: input,
        metadata: metadata,
        status: "ok",
        started_at: Time.current
      )

      Fiber[:llm_logs_span] = span
      span
    end

    def self.auto_create_trace(span_name)
      trace = LlmLogs::Trace.create!(
        name: "auto:#{span_name}",
        status: "running",
        started_at: Time.current
      )
      Fiber[:llm_logs_trace] = trace
      trace
    end
  end
end
