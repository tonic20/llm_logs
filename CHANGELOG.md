# Changelog

All notable changes to this project will be documented in this file.

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
