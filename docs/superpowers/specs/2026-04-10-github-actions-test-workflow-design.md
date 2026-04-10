# GitHub Actions Test Workflow Design

## Problem

The gem has an RSpec test suite, but there is no GitHub Actions workflow to
run it automatically on pull requests or on changes merged to `main`. That
means regressions can land without any repository-level CI signal.

## Scope

Add a single GitHub Actions workflow that runs the existing test suite for the
gem repository.

In scope:

- GitHub Actions workflow configuration
- PostgreSQL service setup for CI
- Ruby setup and bundler caching
- Database migration step for the dummy Rails app
- Running the full RSpec suite

Out of scope:

- Linting or static analysis jobs
- Release, gem publishing, or packaging workflows
- Multi-version Ruby or Rails matrix testing
- Reworking the local test entrypoints

## Existing Constraints

### Test entrypoint

The repository defines `spec` as the default rake task in `Rakefile`, and the
test suite uses `rspec-rails`.

### Database requirement

The dummy app test database in `spec/dummy/config/database.yml` uses
PostgreSQL on `localhost` with the database name `llm_logs_test`.

### Manual migration requirement

`spec/spec_helper.rb` explicitly disables `maintain_test_schema!` and notes
that migrations are run manually before specs. CI therefore needs an explicit
database setup step before running tests.

### Supported target

The gem requires Ruby `>= 3.3`, and this workflow will test one supported
target only: Ruby `3.3`.

## Recommended Approach

Add one workflow file at `.github/workflows/test.yml` with a single `test`
job.

The job should:

1. Check out the repository
2. Install Ruby `3.3`
3. Cache and install gem dependencies with bundler
4. Start PostgreSQL via a GitHub Actions service container
5. Create the test database schema by running migrations
6. Run the full RSpec suite

This is the simplest workflow that matches how the repository already works
locally.

## Rejected Alternatives

### Add a dedicated CI rake task

We could add a `ci` task that wraps database preparation and specs, then have
GitHub Actions call that task.

Rejected for now because it adds repo code solely to support CI while the
required sequence is short and clear in the workflow itself.

### Use SQLite in CI

We could replace PostgreSQL with SQLite to simplify setup.

Rejected because it would stop matching the repository's configured test
environment and could hide PostgreSQL-specific failures.

### Add a Ruby or Rails matrix

We could test multiple Ruby or Rails versions.

Rejected for now because the user chose a single target setup, and the gem does
not currently document a broader compatibility matrix that needs enforcement in
CI.

## Workflow Design

### Triggers

The workflow runs on:

- `pull_request`
- `push` to `main`

It does not run on pushes to other branches outside pull requests.

### Runner

Use `ubuntu-latest`.

This is the standard GitHub-hosted Linux environment and works well with Ruby,
bundler, and PostgreSQL service containers.

### Ruby setup

Use `ruby/setup-ruby` with:

- Ruby version `3.3`
- `bundler-cache: true`

This keeps the workflow short and uses the maintained setup path for Ruby CI.

### PostgreSQL service

Define a `postgres` service container using a recent PostgreSQL image.

Set:

- `POSTGRES_DB=llm_logs_test`
- `POSTGRES_USER=postgres`
- `POSTGRES_PASSWORD=postgres`

Expose port `5432` and add a health check so the job waits until PostgreSQL is
ready.

### Environment configuration

Set job-level environment values so Rails connects to the local CI database:

- `RAILS_ENV=test`
- `PGHOST=127.0.0.1`
- `PGUSER=postgres`
- `PGPASSWORD=postgres`

The dummy database config already points at `localhost`, so these environment
variables mainly make the connection details explicit and avoid relying on
implicit defaults.

### Database preparation

Run:

- `RAILS_ENV=test bundle exec rake db:create`
- `RAILS_ENV=test bundle exec rake db:migrate`

Because this is a Rails engine with a dummy app, the workflow should run the
engine's exposed rake tasks from the repository root. This uses the dummy app
configuration under the hood while keeping CI setup simple and consistent with
the engine layout.

### Test command

Run `bundle exec rspec`.

This directly exercises the full test suite and avoids hiding the command behind
extra CI-only abstractions.

## Error Handling

### PostgreSQL startup race

The workflow should use the service health check so test commands do not start
before PostgreSQL is ready.

### Migration failures

If migrations fail, the job should stop before running specs. This is desirable
because it surfaces schema drift and setup regressions early.

### Dependency resolution failures

Bundler installation should fail the job immediately if the lockfile and gem
environment are inconsistent.

## Files Changed

### New files

- `.github/workflows/test.yml`

### No application code changes expected

The recommended implementation does not require changes to gem code, specs, the
dummy app, or the rake tasks.

## Success Criteria

The work is complete when:

- A pull request triggers the workflow automatically
- A push to `main` triggers the workflow automatically
- The workflow boots PostgreSQL successfully
- The workflow migrates the test database successfully
- The workflow runs the full RSpec suite
- A failing spec causes the GitHub Actions job to fail
