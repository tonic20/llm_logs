# LlmLogs

Mountable Rails engine for LLM call tracing and prompt management. Auto-instruments [ruby_llm](https://github.com/crmne/ruby_llm) to capture every LLM call as a span within a trace, and provides a web UI for browsing logs and editing prompts.

## Installation

Add to your Gemfile:

```ruby
gem "llm_logs"
```

Run the install generator:

```sh
bin/rails generate llm_logs:install
bin/rails db:migrate
```

Or manually:

```ruby
# config/routes.rb
mount LlmLogs::Engine, at: "/llm_logs"
```

```ruby
# config/initializers/llm_logs.rb
LlmLogs.setup do |config|
  config.enabled = true
  config.auto_instrument = true
  config.prompts_source_path = Rails.root.join("db/data/prompts")
end
```

## Tracing

Wrap operations in a trace block. All `ruby_llm` calls inside become child spans automatically.

```ruby
LlmLogs.trace("strategy_analysis", metadata: { strategy_id: 42 }) do
  chat = RubyLLM.chat(model: "anthropic/claude-sonnet-4")
  chat.ask("Analyze this strategy...")
end
```

Nested traces are supported:

```ruby
LlmLogs.trace("full_pipeline") do
  chat.ask("Step 1...")

  LlmLogs.trace("risk_assessment") do
    chat.ask("What are the risks?")
  end
end
```

LLM calls made outside an explicit trace are auto-wrapped in one.

### What Gets Captured

Each span records:

- Model and provider
- Input messages and output content
- Input, output, and cached token counts
- Duration in milliseconds
- Error messages (on failure)
- Custom metadata

Tool calls are captured as child spans with tool name and arguments.

## Prompt Management

Create prompts with [Mustache](https://mustache.github.io/) templates and auto-versioning.

### Create a Prompt

```ruby
prompt = LlmLogs::Prompt.create!(
  slug: "strategy-analysis",
  name: "Strategy Analysis"
)

prompt.update_content!(
  messages: [
    { "role" => "system", "content" => "You analyze trading strategies for {{app_name}}." },
    { "role" => "user", "content" => "Analyze {{strategy_name}} on the {{timeframe}} timeframe." }
  ],
  model: "claude-sonnet-4",
  model_params: { "temperature" => 0.3, "max_tokens" => 2048 }
)
```

### Load and Render

```ruby
prompt = LlmLogs::Prompt.load("strategy-analysis")
params = prompt.build(
  app_name: "Tradebot",
  strategy_name: "Momentum Alpha",
  timeframe: "4h"
)
# => { model: "claude-sonnet-4", messages: [...], temperature: 0.3, max_tokens: 2048 }
```

### Reasoning Effort

Reasoning models take an effort tier rather than a temperature. Set it like any
other model param, from the admin form or a prompt `.md`:

```yaml
model: gpt-5.6-terra
model_params:
  reasoning_effort: low
```

Values are validated against `LlmLogs.reasoning_effort_options`, which defaults to
`%w[none low medium high xhigh max]` — the union of what current providers accept.
Narrow it if your app targets a single provider (Anthropic has no `none` tier):

```ruby
LlmLogs.setup do |config|
  config.reasoning_effort_options = %w[low medium high]
end
```

Leaving the field blank stores nothing, so the model's own default applies.
Applying the value to a request is the caller's job — the gem stores and validates
it, it does not build your chat object.

### Versioning

Every save creates a new version. Previous versions are never modified.

```ruby
prompt.update_content!(
  messages: [{ "role" => "user", "content" => "Updated prompt" }],
  changelog: "Simplified the prompt"
)

prompt.current_version       # latest
prompt.version(1)            # specific version
prompt.rollback_to!(1)       # creates new version from v1 content
```

### Sync Prompts From Files

Store prompts as Markdown files and sync them into `LlmLogs::Prompt` records with the rake task.

```ruby
# config/initializers/llm_logs.rb
LlmLogs.setup do |config|
  config.prompts_source_path = Rails.root.join("db/data/prompts")
  config.prompt_subfolders = %w[skills fragments templates]
end
```

```sh
bin/rails llm_logs:prompts:sync
```

The syncer reads `*.md` files from each configured subfolder. The subfolder name is added as a prompt tag automatically.

```text
db/data/prompts/
  skills/
    backtest-evaluation.md
  fragments/
    provider-notes.md
  templates/
    trading-memo.md
```

Single-message prompts use the Markdown body as the system message:

```markdown
---
slug: backtest-evaluation
name: Backtest Evaluation
description: How to evaluate backtests
tags: [evaluation]
model: anthropic/claude-sonnet-4
model_params:
  temperature: 0.3
---
Body content here.
```

Multi-message prompts can reference sibling body files:

```markdown
---
slug: trading-memo
name: Trading Memo
model: deepseek/deepseek-v3.2
messages:
  - role: system
    body_file: trading_memo_system.md
  - role: user
    body_file: trading_memo_user.md
---
```

Running the task creates missing prompts, updates metadata, and creates a new prompt version only when messages, model, or model parameters changed.

## Batches

Send latency-insensitive requests through a provider's Batch API for roughly half the cost. LlmLogs persists each request, groups pending requests into a provider batch, reconciles results, and records a trace per request — so batched work shows up in the dashboard alongside synchronous calls.

Batching runs on the **[AWS Bedrock Batch API](#aws-bedrock-batches)** (`CreateModelInvocationJob`) for Anthropic Claude models. Models Bedrock does not serve are not batchable; run them synchronously.

### Enqueue a Request

Requests are persisted immediately and grouped by `purpose` + `model` when submitted:

```ruby
LlmLogs::Batch.enqueue(
  purpose: "chat_summary",
  model: "anthropic.claude-haiku-4-5-20251001-v1:0",
  instructions: "Summarize the conversation in two sentences.",
  input: conversation_text,
  schema: SUMMARY_SCHEMA,          # optional JSON schema Hash for structured output
  routing: { conversation_id: 42 }, # your keys, echoed into the trace metadata
  temperature: 0.2                  # optional
)
```

`routing` is arbitrary metadata you control. It rides along with the request and is copied onto the recorded trace, so you can trace a result back to your own records.

### Handle Results

Register one handler per `purpose`. The gem owns the batch lifecycle; your app owns what happens with each result:

```ruby
# config/initializers/llm_logs.rb
LlmLogs.register_batch_handler("chat_summary", ChatSummaryHandler.new)

class ChatSummaryHandler
  # Called once a request succeeds. `message` is a `LlmLogs::Batch::Adapters::Bedrock::Result`
  # (content, input_tokens, output_tokens, model_id).
  def call(request, message)
    Conversation.find(request.routing["conversation_id"])
      .update!(summary: message.content)
  end

  # Called when a request fails or its batch expires.
  def on_failure(request, error)
    Rails.logger.warn("[chat_summary] #{request.custom_id} failed: #{error}")
  end
end
```

A request is marked `succeeded` only after its handler completes; a handler that raises leaves the request `failed` with the error visible in the dashboard, so a result is never silently lost.

### Submit and Reconcile

Two background jobs drive the lifecycle — schedule them on your own cadence (e.g. via cron, `solid_queue` recurring tasks, or `sidekiq-cron`):

```ruby
# Group this purpose's pending requests into provider batches and submit them.
LlmLogs::Batch::FlushJob.perform_later("chat_summary")

# Reconcile every in-flight batch: fetch results, run handlers, recover stale claims.
LlmLogs::Batch::PollJob.perform_later
```

`FlushJob` claims pending rows with `FOR UPDATE SKIP LOCKED`, so concurrent runs never double-submit. `PollJob` reconciles all unfinished batches and recovers requests stranded by an interrupted submission. Both are idempotent at the request level — already-resolved requests are skipped on re-run.

### AWS Bedrock batches

Anthropic Claude models can batch through the AWS Bedrock Batch API. Bedrock batching is file-based: LlmLogs writes a JSONL manifest to S3, starts a `CreateModelInvocationJob`, and reads the results back from S3. The enqueue/handler/flush/reconcile flow above is identical — only the backend differs.

Add the AWS SDKs to your app's Gemfile:

```ruby
gem "aws-sdk-bedrock"
gem "aws-sdk-s3"
```

Configure the Bedrock backend and register its adapter, pointing it at an S3 bucket and an IAM role Bedrock can assume:

```ruby
# config/initializers/llm_logs.rb
LlmLogs.configuration.bedrock_batch = LlmLogs::Configuration::BedrockBatch.new(
  role_arn:      "arn:aws:iam::<account>:role/<bedrock-batch-role>", # role Bedrock assumes to read/write S3
  s3_bucket:     "my-bedrock-batch-bucket",                          # must be in the model's region
  s3_prefix:     "llm-batch",
  min_records:   100,                                                # Bedrock's minimum records per job
  model_matcher: /\Aanthropic\./,                                    # model ids that route to Bedrock
  region:        "us-east-1"
)
LlmLogs.register_batch_adapter(:bedrock, LlmLogs::Batch::Adapters::Bedrock.new)
```

Provider selection is per model: `LlmLogs::Batch.batch_provider_for(model)` returns `:bedrock` when the adapter is registered and `model_matcher` matches, otherwise `nil` (not batchable — run it synchronously). Bedrock enforces a **minimum records per job**, so check `LlmLogs::Batch.min_records_for(model)` and fall back to a synchronous call when a batch would be under the floor.

The adapter builds its AWS clients from the ambient credential chain by default; inject your own to authenticate explicitly:

```ruby
LlmLogs::Batch::Adapters::Bedrock.new(
  s3:      Aws::S3::Client.new(region: "us-east-1", credentials: creds),
  bedrock: Aws::Bedrock::Client.new(region: "us-east-1", credentials: creds)
)
```

**Prerequisites:** an S3 bucket in the model's region, and an IAM service role trusting `bedrock.amazonaws.com` with `s3:GetObject`/`s3:PutObject` on the bucket prefix. The principal that calls the API needs `bedrock:CreateModelInvocationJob`, `bedrock:GetModelInvocationJob`, and `iam:PassRole` on that role.

## Web UI

Browse traces and manage prompts at `/llm_logs`.

**Traces** — list with filtering by status, drill into hierarchical span trees with collapsible input/output.

**Prompts** — CRUD with Mustache template editor, model configuration, and version history.

**Batches** — list batches with status and request counts, drill into per-request results, tokens, routing metadata, and linked traces.

## Configuration

```ruby
LlmLogs.setup do |config|
  config.enabled = true                                      # master switch for logging
  config.auto_instrument = true                              # subscribe to ruby_llm notifications (needs RubyLLM.config.instrumenter = ActiveSupport::Notifications)
  config.retention_days = 30                                 # for future cleanup job
  config.prompts_source_path = Rails.root.join("db/data/prompts")
  config.prompt_subfolders = %w[skills fragments templates]
  config.batch_enabled = true                                # enable the batch API integration
  config.page_size = 50                                      # rows per page on all index pages
end
```

## ruby_llm 2.0 integration

With `auto_instrument` on, LlmLogs subscribes to ruby_llm's `chat.ruby_llm` and `tool_call.ruby_llm` notifications: one `llm` span per provider round and one tool span per tool call, all siblings under the trace. Tokens and cost come from each round's usage entries. This requires `RubyLLM.config.instrumenter` to be `ActiveSupport::Notifications`; the Railtie sets that default, and `LlmLogs::Instrumentation::RubyLlmChat.install!` sets it when unset.

### Patches for ruby_llm 2.0.x

The engine prepends four fixes (`LlmLogs::RubyLLMPatches`) that ruby_llm 2.0.0 lacks. They install only on ruby_llm >= 2.0.0, and log a warning on 2.1 or later so you re-check them. Drop each once upstream ships the fix:

- **BedrockSigV4** re-signs every Bedrock attempt at send time. Upstream signs once before the retry middleware, so a retry after a long timeout replays an expired signature (403 "Signature expired"). Drop when upstream signs per attempt.
- **ConverseOpenAIReasoning** sends reasoning effort to OpenAI GPT models on Bedrock Converse as `additionalModelRequestFields: {reasoning: {effort: ...}}` (including `none`). Upstream sends `reasoning_effort`, which Bedrock rejects. Claude, Nova, and gpt-oss are unchanged. Drop when upstream sends the GPT shape.
- **ConverseForeignReasoning** replays earlier assistant reasoning (`reasoningContent`) on Bedrock Converse only when the target is an Anthropic model. Upstream replays it to every model, so a chat Claude answered and an OpenAI GPT model continues fails with "This model doesn't support the reasoningContent.reasoningText.text field". Other models whose id names a vendor (`openai.`, `amazon.`, ...) get no reasoning blocks. Claude targets, Mantle, and application-inference-profile ARNs are unchanged. Drop when upstream replays Converse reasoning only to models that accept it.
- **RetrySSLError** adds `Faraday::SSLError` (for example "SSL_connect ... unexpected eof") to the retried exceptions. This is the same trade-off ruby_llm already accepts for read timeouts: a request that reached the server may be sent twice. ruby_llm's `retry_if` still refuses to retry requests marked non-idempotent and streams that already delivered content. Drop when upstream retries `Faraday::SSLError`.

## Requirements

- Rails 8.0+
- Ruby 3.3+
- PostgreSQL

## License

MIT

## Database support

Prompts, prompt versions, tag filters, traces, spans, and their UI support PostgreSQL and SQLite. PostgreSQL retains JSONB and array tags; SQLite uses JSON columns and `json_each` for exact tag matching. Provider batch execution requires PostgreSQL; direct calls and jobs raise `LlmLogs::Batch::UnsupportedAdapter` on SQLite. `LlmLogs::Batch.supported_adapter?` reports the capability.

Run the shared SQLite tests with `LLM_LOGS_DATABASE=sqlite bundle exec rspec`; PostgreSQL remains the default. SQLite migrations run from the gem's install chain before tests. `script/verify_migrations.rb` verifies install, rollback, and schema reload **only on a disposable database** with `LLM_LOGS_DISPOSABLE_DATABASE=1` and an explicit `DATABASE_URL`.
