require "spec_helper"

RSpec.describe "LlmLogs::Traces", type: :request do
  let!(:trace) do
    LlmLogs::Trace.create!(
      name: "test_trace",
      status: "completed",
      started_at: 1.hour.ago,
      completed_at: Time.current,
      duration_ms: 1500.0,
      total_input_tokens: 500,
      total_output_tokens: 200,
      total_cost: 0.0035
    )
  end

  let!(:span) do
    LlmLogs::Span.create!(
      trace: trace,
      name: "chat.complete",
      span_type: "llm",
      model: "claude-sonnet-4",
      provider: "anthropic",
      input: [{ "role" => "user", "content" => "Hello" }],
      output: { "content" => "Hi there!" },
      input_tokens: 500,
      output_tokens: 200,
      started_at: 1.hour.ago,
      completed_at: Time.current,
      duration_ms: 1500.0
    )
  end

  describe "GET /llm_logs" do
    it "renders the traces index" do
      get "/llm_logs"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("test_trace")
    end

    it "filters traces by prompt_version_id and shows filter banner" do
      prompt = LlmLogs::Prompt.create!(slug: "test", name: "Test Prompt")
      prompt.update_content!(messages: [{ "role" => "user", "content" => "Hello" }])
      version = prompt.current_version
      trace.update!(prompt_version: version)

      other_trace = LlmLogs::Trace.create!(
        name: "other_trace", status: "completed",
        started_at: Time.current
      )

      get "/llm_logs", params: { prompt_version_id: version.id }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("test_trace")
      expect(response.body).not_to include("other_trace")
      expect(response.body).to include("Filtering by prompt:")
      expect(response.body).to include("Test Prompt")
      expect(response.body).to include("Clear filter")
    end
  end

  describe "GET /llm_logs/traces/:id" do
    it "renders the trace detail with span tree" do
      get "/llm_logs/traces/#{trace.id}"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("test_trace")
      expect(response.body).to include("chat.complete")
      expect(response.body).to include("claude-sonnet-4")
    end

    it "shows prompt version link when present" do
      prompt = LlmLogs::Prompt.create!(slug: "test", name: "Test Prompt")
      prompt.update_content!(messages: [{ "role" => "user", "content" => "Hello" }])
      version = prompt.current_version
      trace.update!(prompt_version: version)

      get "/llm_logs/traces/#{trace.id}"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Test Prompt")
      expect(response.body).to include("v1")
    end
  end

  describe "GET /llm_logs/traces/:trace_id/spans/:id" do
    it "renders the span detail" do
      get "/llm_logs/traces/#{trace.id}/spans/#{span.id}"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("chat.complete")
      expect(response.body).to include("Hello")
    end
  end

end
