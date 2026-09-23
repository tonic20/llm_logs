require "spec_helper"

RSpec.describe "Prompt and trace writes across connections" do
  self.use_transactional_tests = false

  it "retains a prompt edit alongside an independent trace write" do
    slug = "connection-check-#{SecureRandom.hex(5)}"
    prompt = LlmLogs::Prompt.create!(slug: slug, name: "Connection check")
    trace_id = nil
    ready = Queue.new
    gate = Queue.new
    writers = [
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          ready << true
          gate.pop
          LlmLogs::Prompt.find(prompt.id).update_content!(messages: [{"role" => "user", "content" => "Stored edit"}])
        end
      end,
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          ready << true
          gate.pop
          LlmLogs.trace(slug) do |trace|
            trace_id = trace.id
            span = LlmLogs::Tracer.start_span(name: "test", span_type: "llm", input: {"message" => "Stored input"})
            span.output = {"content" => "Stored output"}
            span.finish
          end
        end
      end
    ]
    2.times { ready.pop }
    2.times { gate << true }
    writers.each(&:value)
    expect(prompt.current_version.messages.first["content"]).to eq("Stored edit")
    expect(LlmLogs::Trace.find(trace_id).spans.first.output["content"]).to eq("Stored output")
  ensure
    writers&.each(&:join)
    LlmLogs::Trace.find_by(id: trace_id)&.destroy!
    prompt&.destroy!
  end
end
