require "spec_helper"

RSpec.describe "LlmLogs::Batches", type: :request do
  let!(:batch) do
    LlmLogs::Batch.create!(purpose: "chat_summary", model: "gpt-5.4-mini", status: "reconciled",
                           openai_batch_id: "batch_abc", request_count: 2, submitted_at: 1.hour.ago)
  end

  it "renders the batches index" do
    get "/llm_logs/batches"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("chat_summary")
    expect(response.body).to include("batch_abc")
    expect(response.body).to include("##{batch.id}")
  end

  it "shows the provider for each batch" do
    LlmLogs::Batch.create!(purpose: "eval_judge", model: "anthropic.claude", provider: "bedrock", status: "submitted", provider_batch_id: "arn:job")
    get "/llm_logs/batches"
    expect(response.body).to include("bedrock")
  end

  it "renders a batch show with its requests" do
    expected = "Recognises the collar battery is critically low and tells the owner to charge it. Concise and reassuring."
    trace = LlmLogs::Trace.create!(name: "chat_summary", status: "completed", started_at: Time.current)
    batch.requests.create!(
      custom_id: "req_1",
      purpose: "chat_summary",
      model: "gpt-5.4-mini",
      status: "succeeded",
      trace_id: trace.id,
      routing: {
        "expected" => expected,
        "dimension" => "expectation",
        "scenario_key" => "low_battery_beeping",
        "prompt_version_id" => 218
      }
    )

    get "/llm_logs/batches/#{batch.id}"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("req_1")
    expect(response.body).to include("##{trace.id}")
    page = Nokogiri::HTML(response.body)
    expect(page.at_css("a[href='/llm_logs/traces/#{trace.id}']").text).to eq("##{trace.id}")
    custom_id_header = page.at_css("th[data-column='custom-id']")
    expect(custom_id_header["class"]).to include("w-56")
    routing = page.at_css("[data-routing]")
    expect(routing.text).to include("expected", "dimension", "expectation", "scenario_key", "low_battery_beeping")
    expect(routing.text).to include("Recognises the collar battery is critically low")
    expect(routing.text).not_to include(expected)
    expect(routing.at_css("[title='#{expected}']")).to be_present
    expect(response.body).not_to include(batch.requests.first.routing.to_json)
  end
end
