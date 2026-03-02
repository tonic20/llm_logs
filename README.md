# LlmLogs

Mountable Rails engine for LLM call tracing and prompt management. Auto-instruments [ruby_llm](https://github.com/crmne/ruby_llm) to capture every LLM call as a span within a trace, and provides a web UI for browsing logs and editing prompts.

## Installation

Add to your Gemfile:

```ruby
gem "llm_logs", github: "tonic20/llm_logs"
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

## Web UI

Browse traces and manage prompts at `/llm_logs`.

**Traces** — list with filtering by status, drill into hierarchical span trees with collapsible input/output.

**Prompts** — CRUD with Mustache template editor, model configuration, and version history.

## Configuration

```ruby
LlmLogs.setup do |config|
  config.enabled = true               # master switch for logging
  config.auto_instrument = true       # auto-prepend on RubyLLM::Chat
  config.retention_days = 30          # for future cleanup job
end
```

## Requirements

- Rails 8.0+
- Ruby 3.3+
- PostgreSQL

## License

MIT
