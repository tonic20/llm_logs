require "spec_helper"
require "aws-sdk-bedrock"
require "aws-sdk-s3"

RSpec.describe LlmLogs::Batch::Adapters::Bedrock do
  let(:s3) { Aws::S3::Client.new(stub_responses: true, region: "us-east-1") }
  let(:bedrock) { Aws::Bedrock::Client.new(stub_responses: true, region: "us-east-1") }
  let(:config) do
    LlmLogs::Configuration::BedrockBatch.new(
      role_arn: "arn:aws:iam::1:role/r", s3_bucket: "bucket", s3_prefix: "batch",
      min_records: 100, model_matcher: /\Aanthropic\./, region: "us-east-1"
    )
  end
  let(:adapter) { described_class.new(config: config, s3: s3, bedrock: bedrock) }
  let(:batch) { LlmLogs::Batch.create!(purpose: "eval_judge", model: "anthropic.claude-sonnet", status: "pending", provider: "bedrock") }
  let(:request) do
    batch.requests.create!(custom_id: "req_abc12345", purpose: "eval_judge", model: "anthropic.claude-sonnet", status: "submitted",
                           payload: {"input" => "Rate this.", "instructions" => "You are a judge.", "schema" => {"name" => "eval_judge", "schema" => {"type" => "object"}}})
  end

  it "writes a JSONL manifest to S3 and starts a model invocation job" do
    put_calls = []
    s3.stub_responses(:put_object, ->(ctx) { put_calls << ctx.params; {} })
    bedrock.stub_responses(:create_model_invocation_job, {job_arn: "arn:aws:bedrock:us-east-1:1:model-invocation-job/xyz"})
    request

    result = adapter.submit(batch, batch.requests.to_a)

    manifest = put_calls.first[:body]
    line = JSON.parse(manifest.lines.first)
    expect(line["recordId"]).to eq("req_abc12345")
    expect(line.dig("modelInput", "anthropic_version")).to eq("bedrock-2023-05-31")
    expect(result[:provider_batch_id]).to eq("arn:aws:bedrock:us-east-1:1:model-invocation-job/xyz")
    expect(result[:provider_metadata]["s3_input_uri"]).to start_with("s3://bucket/batch/")
  end

  it "maps job status to a terminal status" do
    batch.update!(provider_batch_id: "arn:job")
    # aws-sdk-bedrock's response-shape validator (client-side stub checking, not our code)
    # requires job_arn/model_id/role_arn/submit_time/input_data_config alongside status --
    # the brief's minimal {status:, output_data_config:} stub predates this gem version's
    # stricter required-member set, so the extra fields below are filled in to satisfy it.
    bedrock.stub_responses(:get_model_invocation_job, {
      job_arn: "arn:job", model_id: "anthropic.claude-sonnet", role_arn: "arn:aws:iam::1:role/r",
      submit_time: Time.now, status: "Completed",
      input_data_config: {s3_input_data_config: {s3_uri: "s3://bucket/batch/input.jsonl"}},
      output_data_config: {s3_output_data_config: {s3_uri: "s3://bucket/batch/out/"}}
    })
    expect(adapter.terminal_status(batch)).to eq("completed")
  end

  it "parses the S3 output JSONL into messages keyed by recordId" do
    batch.update!(provider_batch_id: "arn:job", provider_metadata: {"s3_output_uri" => "s3://bucket/batch/1/out/", "job_id" => "1", "input_basename" => "input.jsonl"})
    output = {"recordId" => "req_abc12345",
              "modelOutput" => {"content" => [{"type" => "text", "text" => "{\"score\":5}"}],
                                "usage" => {"input_tokens" => 12, "output_tokens" => 3},
                                "model" => "anthropic.claude-sonnet"}}.to_json
    s3.stub_responses(:get_object, {body: StringIO.new(output + "\n")})
    messages = adapter.results(batch)
    msg = messages["req_abc12345"]
    expect(msg.content).to eq("{\"score\":5}")
    expect(msg.input_tokens).to eq(12)
    expect(msg.output_tokens).to eq(3)
    expect(msg.model_id).to eq("anthropic.claude-sonnet")
  end

  it "collects recordIds whose output line carries an error" do
    batch.update!(provider_batch_id: "arn:job", provider_metadata: {"s3_output_uri" => "s3://bucket/batch/1/out/", "job_id" => "1", "input_basename" => "input.jsonl"})
    body = {"recordId" => "req_bad", "error" => {"message" => "throttled"}}.to_json
    s3.stub_responses(:get_object, {body: StringIO.new(body + "\n")})
    expect(adapter.error_ids(batch)).to eq(["req_bad"])
  end
end
