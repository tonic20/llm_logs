# GitHub Actions Test Workflow Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a GitHub Actions workflow that runs the full gem test suite on pull requests and pushes to `main`.

**Architecture:** The implementation is configuration-only. Add a single GitHub Actions workflow file that uses `ubuntu-latest`, installs Ruby 3.3 with bundler caching, boots PostgreSQL as a service, prepares the test database through the engine's root rake tasks, and runs `bundle exec rspec`.

**Tech Stack:** GitHub Actions, Ruby 3.3, Bundler, PostgreSQL, Rails engine rake tasks, RSpec

**Spec:** `docs/superpowers/specs/2026-04-10-github-actions-test-workflow-design.md`

**Working directory:** `/Users/anton/workspace/llm_logs`

**Run tests with:** `cd /Users/anton/workspace/llm_logs && bundle exec rspec`

---

## File Structure

### New files
- `.github/workflows/test.yml` — CI workflow that installs dependencies, starts PostgreSQL, prepares the test database, and runs the RSpec suite

### Existing files expected to remain unchanged
- `Rakefile` — already exposes the root `db:*` tasks the workflow should call
- `spec/spec_helper.rb` — already documents that migrations run manually before specs
- `spec/dummy/config/database.yml` — already points tests at PostgreSQL on localhost

### Verification commands
- `ruby -e 'require "yaml"; YAML.load_file(".github/workflows/test.yml")'` — syntax check for the workflow file
- `RAILS_ENV=test bundle exec rake db:create db:migrate` — validate the CI database preparation sequence
- `bundle exec rspec` — validate the full test suite after setup

### Implementation note

This is a CI configuration change, not an application behavior change, so there
is no meaningful new RSpec example to add first. Validation comes from checking
the workflow YAML parses and from exercising the same database/test commands the
workflow will run.

---

### Task 1: Add the GitHub Actions workflow

**Files:**
- Create: `.github/workflows/test.yml`
- Verify: `.github/workflows/test.yml`

- [ ] **Step 1: Confirm the workflow does not already exist**

Run:

```bash
cd /Users/anton/workspace/llm_logs
rg --files .github/workflows
```

Expected: no existing workflow file for running the gem test suite, or at least
no `test.yml` that already covers this job.

- [ ] **Step 2: Create the workflow file**

Create `.github/workflows/test.yml` with:

```yaml
name: Test

on:
  pull_request:
  push:
    branches:
      - main

jobs:
  test:
    runs-on: ubuntu-latest

    services:
      postgres:
        image: postgres:16
        env:
          POSTGRES_DB: llm_logs_test
          POSTGRES_USER: postgres
          POSTGRES_PASSWORD: postgres
        ports:
          - 5432:5432
        options: >-
          --health-cmd "pg_isready -U postgres -d llm_logs_test"
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5

    env:
      RAILS_ENV: test
      PGHOST: 127.0.0.1
      PGUSER: postgres
      PGPASSWORD: postgres

    steps:
      - name: Check out code
        uses: actions/checkout@v4

      - name: Set up Ruby
        uses: ruby/setup-ruby@v1
        with:
          ruby-version: "3.3"
          bundler-cache: true

      - name: Create database
        run: bundle exec rake db:create

      - name: Run migrations
        run: bundle exec rake db:migrate

      - name: Run test suite
        run: bundle exec rspec
```

- [ ] **Step 3: Validate the workflow YAML syntax**

Run:

```bash
cd /Users/anton/workspace/llm_logs
ruby -e 'require "yaml"; YAML.load_file(".github/workflows/test.yml")'
```

Expected: command exits successfully with no output.

- [ ] **Step 4: Verify the database preparation commands locally**

Run:

```bash
cd /Users/anton/workspace/llm_logs
RAILS_ENV=test bundle exec rake db:create
RAILS_ENV=test bundle exec rake db:migrate
```

Expected: both commands exit successfully when PostgreSQL is available locally.
If the environment lacks PostgreSQL access, note that explicitly and continue
to the next verification step that can still run.

- [ ] **Step 5: Run the full test suite**

Run:

```bash
cd /Users/anton/workspace/llm_logs
bundle exec rspec
```

Expected: full suite passes.

- [ ] **Step 6: Inspect the diff**

Run:

```bash
cd /Users/anton/workspace/llm_logs
git diff -- .github/workflows/test.yml
```

Expected: only the new workflow file appears, and it matches the approved spec:
single Ruby 3.3 target, PR plus `main` triggers, PostgreSQL-backed test run.

- [ ] **Step 7: Commit**

```bash
cd /Users/anton/workspace/llm_logs
git add .github/workflows/test.yml
git commit -m "ci: add GitHub Actions test workflow"
```
