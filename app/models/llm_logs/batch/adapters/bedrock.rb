require "json"
require "securerandom"

module LlmLogs
  class Batch
    module Adapters
      # AWS Bedrock Batch API (CreateModelInvocationJob). Writes a JSONL manifest to S3,
      # starts an async job, polls it, and reads the output JSONL back from S3. Unlike the
      # OpenAI adapter, submission/output is file-based (S3) rather than an upload endpoint.
      class Bedrock
        ANTHROPIC_VERSION = "bedrock-2023-05-31"
        DEFAULT_MAX_TOKENS = 1024

        Result = Struct.new(:content, :input_tokens, :output_tokens, :model_id, keyword_init: true)

        def initialize(config: LlmLogs.bedrock_batch, s3: nil, bedrock: nil)
          @config = config
          @s3 = s3
          @bedrock = bedrock
        end

        def submit(batch, requests)
          key = "#{@config.s3_prefix}/#{batch.id}/input.jsonl"
          manifest = requests.map { |r| JSON.generate(record_for(r)) }.join("\n") + "\n"
          s3.put_object(bucket: @config.s3_bucket, key: key, body: manifest)

          input_uri = "s3://#{@config.s3_bucket}/#{key}"
          output_uri = "s3://#{@config.s3_bucket}/#{@config.s3_prefix}/#{batch.id}/out/"
          job = bedrock.create_model_invocation_job(
            job_name: job_name_for(batch),
            role_arn: @config.role_arn,
            model_id: batch.model,
            input_data_config: {s3_input_data_config: {s3_uri: input_uri}},
            output_data_config: {s3_output_data_config: {s3_uri: output_uri}}
          )

          {
            provider_batch_id: job.job_arn,
            openai_batch_id: nil,
            provider_metadata: {
              "s3_input_uri" => input_uri,
              "s3_output_uri" => output_uri,
              "job_id" => job.job_arn.split("/").last,
              "input_basename" => "input.jsonl"
            }
          }
        end

        def terminal_status(batch)
          job = bedrock.get_model_invocation_job(job_identifier: batch.provider_batch_id)
          case job.status
          when "Completed" then "completed"
          when "Failed", "Stopped", "PartiallyCompleted" then "failed"
          when "Expired" then "expired"
          else "in_progress"
          end
        end

        def results(batch)
          parsed_output(batch).each_with_object({}) do |line, acc|
            next if line["recordId"].nil? || line["error"]

            output = line["modelOutput"] || {}
            usage = output["usage"] || {}
            acc[line["recordId"]] = Result.new(
              content: extract_content(output),
              input_tokens: usage["input_tokens"],
              output_tokens: usage["output_tokens"],
              model_id: output["model"] || batch.model
            )
          end
        end

        def error_ids(batch)
          parsed_output(batch).filter_map { |line| line["recordId"] if line["error"] }
        end

        private

        # Bedrock jobName allows only [A-Za-z0-9] plus '-', '+', '.'. Purposes such as
        # "eval_judge" contain underscores, so map any disallowed character to a hyphen.
        def job_name_for(batch)
          "llmlogs-#{batch.purpose}-#{batch.id}-#{SecureRandom.hex(4)}".gsub(/[^a-zA-Z0-9+.-]/, "-")
        end

        # One JSONL record: {recordId, modelInput: <native Anthropic Messages body>}.
        def record_for(request)
          payload = request.payload
          {recordId: request.custom_id, modelInput: model_input(payload)}
        end

        def model_input(payload)
          body = {
            "anthropic_version" => ANTHROPIC_VERSION,
            "max_tokens" => DEFAULT_MAX_TOKENS,
            "messages" => [{"role" => "user", "content" => payload["input"]}]
          }
          body["system"] = payload["instructions"] if payload["instructions"]
          body.merge!(structured_output(payload["schema"])) if payload["schema"]
          body
        end

        # Anthropic structured output via a single forced tool (verify encoding against QA).
        def structured_output(schema)
          spec = schema["schema"] || schema
          {
            "tools" => [{"name" => schema["name"] || "response", "description" => "Return the structured response.", "input_schema" => spec}],
            "tool_choice" => {"type" => "tool", "name" => schema["name"] || "response"}
          }
        end

        def extract_content(output)
          blocks = output["content"] || []
          tool = blocks.find { |b| b["type"] == "tool_use" }
          return JSON.generate(tool["input"]) if tool

          blocks.filter_map { |b| b["text"] if b["type"] == "text" }.join
        end

        def parsed_output(batch)
          meta = batch.provider_metadata
          key = "#{@config.s3_prefix}/#{batch.id}/out/#{meta["job_id"]}/#{meta["input_basename"]}.out"
          body = s3.get_object(bucket: @config.s3_bucket, key: key).body.read
          body.each_line.filter_map { |l| JSON.parse(l) unless l.strip.empty? }
        end

        def s3
          @s3 ||= (require "aws-sdk-s3"; Aws::S3::Client.new(region: @config.region))
        end

        def bedrock
          @bedrock ||= (require "aws-sdk-bedrock"; Aws::Bedrock::Client.new(region: @config.region))
        end
      end
    end
  end
end
