# Changelog

All notable changes to this project will be documented in this file.

## [0.2.2] - 2026-06-11

### Added
- OpenAI Responses Batch API support: requests are persisted, grouped into provider
  batches, submitted, reconciled, and recorded as a trace per request — so batched work
  appears in the dashboard alongside synchronous calls. Roughly half the cost when
  latency doesn't matter.
- Purpose-based result handlers: register one handler per purpose to route each result
  (and failure) into your app. A request is marked succeeded only after its handler
  completes, so failures stay visible instead of being silently lost.
- Background flush and poll jobs with race-safe request claiming (`FOR UPDATE SKIP
  LOCKED`) and recovery of requests stranded by an interrupted submission.
- Batches dashboard for browsing batches and per-request results, tokens, metadata, and
  linked traces.
- Batch configuration options (`batch_enabled`, `batch_provider`).

### Changed
- Trace names identify the operation consistently across synchronous and batch
  execution, with execution mode recorded in trace metadata.
- Trace detail pages show the LLM model as a summary card; it was previously visible
  only by opening an individual span.
- Pinned the `ruby_llm` development dependency to `~> 1.16`.

### Fixed
- Structured (schema) LLM responses are stored and displayed as JSON instead of Ruby
  inspect syntax (`"key" => "value"`), which previously rendered as an escaped,
  unparseable blob in the dashboard.

## [0.1.6] - 2026-06-04

### Fixed
- Prompt message rendering no longer hides custom tags. `render_markdown` escapes
  `&`/`<`/`>` before Markdown so prompt delimiters such as `<user_request>` show as
  visible text on the prompt and version detail pages, instead of being parsed as
  unknown HTML and stripped by the sanitizer. Standard Markdown (headings, bold,
  lists, tables, code) still renders.

## [0.1.5] - 2026-06-03

### Fixed
- Trace/span context now propagates into child fibers. It is stored in `Fiber[]`
  (inherited by child fibers) instead of `Thread.current[:key]` (fiber-local and
  *not* inherited). Tracing driven inside a fiber scheduler such as
  socketry/async no longer loses the active trace, which previously caused
  `start_span` to spawn orphan `auto:*` traces and split parent/child spans
  across separate traces.

## [0.1.4] - 2026-04-22

### Added
- Sortable columns (Name, Slug, Updated) on the `/llm_logs/prompts` index with a default sort by name ascending.
- `AGENTS.md` with contribution rules for AI agents working on the gem.

## [0.1.3] - 2026-04-22

### Added
- `tags` array column on prompts with GIN index and `with_tag` / `with_any_tag` scopes.
- Tag filter on the `/llm_logs/prompts` index and comma-separated tag input in the form.
- `LlmLogs::PromptSyncer` service and `llm_logs:prompts:sync` rake task for syncing prompts from a configured source directory.
- `LlmLogs::Configuration` with `prompts_source_path` and `prompt_subfolders` (defaults to `skills`, `fragments`, `templates`).
- Markdown rendering for prompt messages on prompt detail and version detail pages.

### Changed
- SDK usage examples on prompt detail pages are collapsed by default and can be expanded inline.
- Configuration now uses a single `LlmLogs.setup` block for core logging settings and prompt sync settings.

## [0.1.2] - 2026-04-11

### Changed
- Simplified the installation instructions to use `gem "llm_logs"` now that the gem is published on RubyGems.

## [0.1.1] - 2026-04-10

### Added
- GitHub Actions workflow that runs the full RSpec suite on pull requests and pushes to `main`.

### Changed
- CI now runs the PostgreSQL-backed test setup with an explicit `DATABASE_URL` and a job timeout for more reliable automated test runs.

## [0.1.0] - 2026-04-10

### Added
- Initial release of the `llm_logs` mountable Rails engine for tracing `ruby_llm` calls and browsing logs through a built-in web UI.
- Prompt management with Mustache-based templates, versioned prompt content, prompt history views, and rollback support.
- Prompt version controls, including compare, restore, delete protections, and trace-to-version links in the UI.

### Changed
- Improved trace and prompt browsing with pagination, cached token display, clearer token breakdowns, and general UI navigation polish.
- Tightened gem metadata for release readiness, including homepage and source links plus a Rails `~> 8.0` dependency.

### Fixed
- Improved initial release quality with fixes for tool I/O capture, token capture on errored spans, inline validation errors, Turbo confirm support, JSON/span rendering, and prompt diff behavior.
