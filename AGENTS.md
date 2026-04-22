# AGENTS.md

Rules for AI agents working on the `llm_logs` Ruby gem (a mountable Rails engine).

## Project layout

- `lib/llm_logs/` — gem code (engine, tracer, configuration, instrumentation).
- `lib/llm_logs/version.rb` — single source of truth for the gem version.
- `app/` — engine controllers, models, views, helpers, services (namespaced under `LlmLogs::`).
- `db/migrate/` — engine migrations, copied into host apps via the install generator.
- `lib/generators/llm_logs/` — install generator and templates.
- `lib/tasks/` — rake tasks exposed to host apps.
- `spec/` — RSpec tests (with a `spec/dummy` host Rails app).
- `CHANGELOG.md` — human-edited changelog, Keep a Changelog format.

## Golden rules

1. **Bump the version at the end of every feature or bugfix.** Edit `lib/llm_logs/version.rb` and add a matching entry to `CHANGELOG.md` before the work is considered done. This is easy to forget — treat it as part of the definition of done for any change that ships behavior.
2. **Never ship without running the spec suite.** `bundle exec rspec` must be green.
3. **Keep everything under the `LlmLogs::` namespace.** No top-level constants. Models, controllers, services, helpers, jobs all live under `LlmLogs::`.
4. **Don't break host apps.** The gem mounts into other Rails apps — migrations, routes, and assets must stay additive and idempotent.

## Versioning

- Follow SemVer.
  - Patch (`0.1.3 → 0.1.4`): bugfixes, internal refactors, doc-only changes with no user-visible behavior shift.
  - Minor (`0.1.3 → 0.2.0`): new features, new configuration options, new public APIs (pre-1.0 may also include breaking changes here, but call them out loudly).
  - Major (`0.1.3 → 1.0.0`+): breaking changes in stable releases.
- Every version bump must have a corresponding `## [x.y.z] - YYYY-MM-DD` section in `CHANGELOG.md` with Added / Changed / Fixed / Removed subsections as needed.
- Do **not** tag or push gems (`gem push`) unless explicitly asked — that is a human-gated action.

## Feature workflow

1. Understand the request; look for skills/brainstorming if it is non-trivial.
2. Write or update specs first when the change is testable (request specs for controllers/views, model specs for scopes/validations).
3. Implement the change using existing patterns — mirror the style of neighboring files.
4. Run `bundle exec rspec`.
5. **Bump the version in `lib/llm_logs/version.rb`.**
6. **Add a changelog entry in `CHANGELOG.md`** dated today, describing the change from a user's perspective.
7. Commit with a short imperative subject line (see recent `git log` for tone).

## Rails / Ruby conventions

- Ruby `>= 3.3`, Rails `~> 8.0`. Avoid syntax or APIs that require newer.
- Prefer fat models, thin controllers. Push non-trivial logic into `app/services/llm_logs/`.
- Controllers should use strong params and whitelist any user-supplied column names (e.g. sort columns) against a known hash — never interpolate user input into `order(...)`.
- Views use ERB + Tailwind utility classes consistent with the existing UI.
- Use Kaminari for pagination (already a dependency).
- Markdown rendering goes through `LlmLogs::FormattingHelper#render_markdown` with sanitization.
- Migrations must be reversible and namespaced (`llm_logs_` table prefix).

## Testing

- RSpec + the dummy app under `spec/dummy`. Request specs live in `spec/requests/llm_logs/`.
- Tests run against Postgres (see `spec/spec_helper.rb` and the GitHub Actions workflow). Don't assume SQLite.
- Prefer request specs over controller specs.
- When adding a scope, column, or service, add a focused spec for it.

## Dependencies

- Add a new runtime dependency only when it is genuinely needed, and add it to `llm_logs.gemspec` with a pessimistic version constraint (`~>`).
- Keep the gem slim — this engine is meant to drop into existing apps with minimal surface.

## Things NOT to do

- Do not edit `Gemfile.lock` by hand; run `bundle install` instead.
- Do not hand-edit `.gem` files in the repo root or `pkg/`.
- Do not introduce host-app-specific assumptions (no references to anyone's internal app, models, or routes).
- Do not leave `binding.pry`, `byebug`, or `puts`-based debugging in committed code.
- Do not rename public APIs, tables, or routes without a corresponding major/minor bump and a migration path.

## Before declaring done

- [ ] Specs pass: `bundle exec rspec`
- [ ] `lib/llm_logs/version.rb` bumped
- [ ] `CHANGELOG.md` updated with today's date and a user-facing summary
- [ ] No stray debug output, commented-out code, or TODOs introduced
