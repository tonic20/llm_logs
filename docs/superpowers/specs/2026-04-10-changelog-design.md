# Changelog Design

## Problem

The repository ships a `changelog_uri` in the gemspec, but there is no
`CHANGELOG.md` file in the repo. That leaves releases without a stable, repo-
visible summary of what changed and makes the metadata link point to a missing
document.

## Scope

Add a retrospective `CHANGELOG.md` that covers the existing released versions:

- `0.1.1`
- `0.1.0`

In scope:

- Creating a new top-level `CHANGELOG.md`
- Summarizing the main shipped changes for `0.1.0`
- Summarizing the main shipped changes for `0.1.1`
- Using a standard changelog structure

Out of scope:

- Reconstructing every historical commit as its own changelog bullet
- Adding unreleased entries
- Backfilling links to issue trackers or PRs that do not already exist
- Changing gem behavior or release automation

## Recommended Format

Use a standard Keep a Changelog style document:

- Title: `# Changelog`
- Short intro sentence explaining notable changes are documented here
- Release sections in reverse chronological order
- Version/date headings in the form `## [0.1.1] - 2026-04-10`
- Standard subsections such as `Added`, `Changed`, and `Fixed` where useful

This is the most recognizable format for gem users and keeps the file easy to
extend in future releases.

## Release Content Strategy

### Version 0.1.1

This section should focus on the work added after the `0.1.0` release commit:

- GitHub Actions workflow for running the test suite
- CI hardening done during the workflow implementation, including explicit
  PostgreSQL connection handling and the job timeout

This is a small patch release, so the section should be concise.

### Version 0.1.0

This section should summarize the initial public feature set visible in the
repository before the `0.1.0` release commit:

- Rails engine for LLM trace capture
- Prompt management with versioned prompt content
- Web UI for browsing traces and managing prompts
- Prompt-version controls added before the initial release, including compare,
  restore, delete protections, and trace-to-version linking
- Key fixes that materially shaped the initial release quality, such as inline
  validation errors, Turbo confirm support, token/tool capture improvements,
  and pagination/UI polish

The goal is not to mirror every commit. The goal is to help a gem user
understand what `0.1.0` contained.

## Tone and Granularity

- Write concise release notes, not a development diary
- Prefer user-facing behavior over implementation details
- Group closely related work into one bullet where that improves readability
- Avoid speculative language and avoid claiming behavior not supported by the
  repo history

## File Changes

### New files

- `CHANGELOG.md`

### Existing files expected to remain unchanged

- `llm_logs.gemspec` already points at `CHANGELOG.md`; no metadata changes are
  required for this task

## Success Criteria

The work is complete when:

- `CHANGELOG.md` exists at the repo root
- The file follows a standard changelog structure
- It includes sections for `0.1.1` and `0.1.0`
- `0.1.1` accurately summarizes the CI/test workflow release
- `0.1.0` accurately summarizes the initial shipped feature set
- The content is concise, readable, and supported by repository history
