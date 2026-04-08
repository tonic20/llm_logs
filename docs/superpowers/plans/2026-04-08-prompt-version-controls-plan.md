# Prompt Version Controls Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add version management actions (restore, delete, compare), trace-to-prompt-version linking, and UI enhancements to the llm_logs gem.

**Architecture:** All changes in the llm_logs gem (Rails engine). Data layer adds a nullable FK from traces to prompt_versions. Auto-capture in `Prompt#build` links traces to versions automatically. Compare mode uses server-side diff via the `diffy` gem. No JS build pipeline — inline vanilla JS for checkbox logic.

**Tech Stack:** Rails 8.0, RSpec, diffy gem, Tailwind CSS (CDN), Turbo

**Spec:** `docs/superpowers/specs/2026-04-08-prompt-version-controls-design.md`

**Working directory:** `/Users/anton/workspace/llm_logs`

**Run tests with:** `cd /Users/anton/workspace/llm_logs && bundle exec rspec`

---

## File Structure

### New files
- `db/migrate/005_add_prompt_version_to_traces.rb` — migration adding FK
- `app/views/llm_logs/prompt_versions/compare.html.erb` — side-by-side diff view
- `spec/requests/llm_logs/prompt_versions_spec.rb` — request specs for new actions
- `spec/models/llm_logs/prompt_version_spec.rb` — model specs for has_many :traces

### Modified files
- `llm_logs.gemspec` — add `diffy` dependency
- `app/models/llm_logs/trace.rb` — add `belongs_to :prompt_version`
- `app/models/llm_logs/prompt_version.rb` — add `has_many :traces`
- `app/models/llm_logs/prompt.rb` — auto-capture in `build`
- `config/routes.rb` — add destroy, restore, compare routes
- `app/controllers/llm_logs/prompt_versions_controller.rb` — add restore, destroy, compare actions
- `app/controllers/llm_logs/traces_controller.rb` — add prompt_version_id filter
- `app/views/llm_logs/prompt_versions/index.html.erb` — checkboxes, current badge, action buttons, inline JS
- `app/views/llm_logs/prompt_versions/show.html.erb` — trace count link
- `app/views/llm_logs/prompts/show.html.erb` — current badge in sidebar
- `app/views/llm_logs/traces/show.html.erb` — prompt version link
- `app/views/llm_logs/traces/index.html.erb` — prompt version filter banner
- `app/views/layouts/llm_logs/application.html.erb` — add alert flash rendering
- `spec/dummy/db/schema.rb` — updated after migration
- `spec/models/llm_logs/prompt_spec.rb` — auto-capture tests
- `spec/models/llm_logs/trace_spec.rb` — prompt_version association tests
- `spec/lib/llm_logs/tracer_spec.rb` — auto-capture integration tests
- `spec/requests/llm_logs/traces_spec.rb` — filter by prompt_version_id tests

---

### Task 1: Migration and model associations

**Files:**
- Create: `db/migrate/005_add_prompt_version_to_traces.rb`
- Modify: `app/models/llm_logs/trace.rb`
- Modify: `app/models/llm_logs/prompt_version.rb`
- Modify: `spec/dummy/db/schema.rb`
- Test: `spec/models/llm_logs/trace_spec.rb`
- Test: `spec/models/llm_logs/prompt_version_spec.rb` (create)

- [ ] **Step 1: Write the failing test for Trace#prompt_version association**

Add to `spec/models/llm_logs/trace_spec.rb`, inside the top-level describe block:

```ruby
describe "#prompt_version" do
  it "can reference a prompt version" do
    prompt = LlmLogs::Prompt.create!(slug: "test", name: "Test")
    prompt.update_content!(messages: [{ "role" => "user", "content" => "Hello" }])
    version = prompt.current_version

    trace = LlmLogs::Trace.create!(
      name: "test", started_at: Time.current, status: "running",
      prompt_version: version
    )

    expect(trace.prompt_version).to eq(version)
  end

  it "is optional" do
    trace = LlmLogs::Trace.create!(name: "test", started_at: Time.current, status: "running")
    expect(trace.prompt_version).to be_nil
  end
end
```

- [ ] **Step 2: Write the failing test for PromptVersion#traces association**

Create `spec/models/llm_logs/prompt_version_spec.rb`:

```ruby
require "spec_helper"

RSpec.describe LlmLogs::PromptVersion do
  describe "#traces" do
    it "returns traces linked to this version" do
      prompt = LlmLogs::Prompt.create!(slug: "test", name: "Test")
      prompt.update_content!(messages: [{ "role" => "user", "content" => "Hello" }])
      version = prompt.current_version

      trace = LlmLogs::Trace.create!(
        name: "test", started_at: Time.current, status: "running",
        prompt_version: version
      )

      expect(version.traces).to eq([trace])
    end

    it "nullifies traces when version is destroyed" do
      prompt = LlmLogs::Prompt.create!(slug: "test", name: "Test")
      prompt.update_content!(messages: [{ "role" => "user", "content" => "v1" }])
      prompt.update_content!(messages: [{ "role" => "user", "content" => "v2" }])
      version = prompt.version(1)

      trace = LlmLogs::Trace.create!(
        name: "test", started_at: Time.current, status: "running",
        prompt_version: version
      )

      version.destroy!
      expect(trace.reload.prompt_version_id).to be_nil
    end
  end
end
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `cd /Users/anton/workspace/llm_logs && bundle exec rspec spec/models/llm_logs/trace_spec.rb spec/models/llm_logs/prompt_version_spec.rb`
Expected: FAIL — `prompt_version` column does not exist

- [ ] **Step 4: Create migration and update models**

Create `db/migrate/005_add_prompt_version_to_traces.rb`:

```ruby
class AddPromptVersionToTraces < ActiveRecord::Migration[8.0]
  def change
    add_reference :llm_logs_traces, :prompt_version,
      foreign_key: { to_table: :llm_logs_prompt_versions, on_delete: :nullify },
      null: true
  end
end
```

Add to `app/models/llm_logs/trace.rb` (after the has_many :spans line):

```ruby
belongs_to :prompt_version, class_name: "LlmLogs::PromptVersion", optional: true
```

Add to `app/models/llm_logs/prompt_version.rb` (after the belongs_to :prompt line):

```ruby
has_many :traces, class_name: "LlmLogs::Trace", dependent: :nullify
```

- [ ] **Step 5: Run and apply migration on test database**

Run: `cd /Users/anton/workspace/llm_logs && RAILS_ENV=test bundle exec rails db:migrate`

- [ ] **Step 6: Run tests to verify they pass**

Run: `cd /Users/anton/workspace/llm_logs && bundle exec rspec spec/models/llm_logs/trace_spec.rb spec/models/llm_logs/prompt_version_spec.rb`
Expected: PASS

- [ ] **Step 7: Add diffy gem dependency**

Add to `llm_logs.gemspec` after the kaminari line:

```ruby
spec.add_dependency "diffy", "~> 3.4"
```

Run: `cd /Users/anton/workspace/llm_logs && bundle install`

- [ ] **Step 8: Commit**

```bash
cd /Users/anton/workspace/llm_logs
git add db/migrate/005_add_prompt_version_to_traces.rb app/models/llm_logs/trace.rb app/models/llm_logs/prompt_version.rb spec/models/llm_logs/trace_spec.rb spec/models/llm_logs/prompt_version_spec.rb spec/dummy/db/schema.rb llm_logs.gemspec Gemfile.lock
git commit -m "feat: add prompt_version FK to traces and diffy dependency"
```

---

### Task 2: Auto-capture prompt version in traces

**Files:**
- Modify: `app/models/llm_logs/prompt.rb`
- Test: `spec/models/llm_logs/prompt_spec.rb`
- Test: `spec/lib/llm_logs/tracer_spec.rb`

- [ ] **Step 1: Write the failing test for auto-capture in Prompt#build**

Add to `spec/models/llm_logs/prompt_spec.rb`, inside the `describe "#build"` block (after the existing tests):

```ruby
it "auto-captures prompt version on the active trace" do
  trace = nil
  LlmLogs::Tracer.start_trace("test") do |t|
    trace = t
    prompt.build(name: "Alice", project: "Tradebot")
  end

  expect(trace.reload.prompt_version).to eq(prompt.current_version)
end

it "does not overwrite prompt_version if already set" do
  other_prompt = LlmLogs::Prompt.create!(slug: "other", name: "Other")
  other_prompt.update_content!(messages: [{ "role" => "user", "content" => "Other" }])
  other_version = other_prompt.current_version

  trace = nil
  LlmLogs::Tracer.start_trace("test") do |t|
    trace = t
    trace.update!(prompt_version: other_version)
    prompt.build(name: "Alice", project: "Tradebot")
  end

  expect(trace.reload.prompt_version).to eq(other_version)
end

it "does not fail when no trace is active" do
  Thread.current[:llm_logs_trace] = nil
  result = prompt.build(name: "Alice", project: "Tradebot")
  expect(result[:messages]).to be_present
end
```

- [ ] **Step 2: Run tests to verify the auto-capture test fails**

Run: `cd /Users/anton/workspace/llm_logs && bundle exec rspec spec/models/llm_logs/prompt_spec.rb`
Expected: First new test FAILS (prompt_version is nil), others pass

- [ ] **Step 3: Implement auto-capture in Prompt#build**

In `app/models/llm_logs/prompt.rb`, replace the `build` method:

```ruby
def build(variables = {})
  ver = current_version
  raise "No versions exist for prompt '#{slug}'" unless ver

  trace = LlmLogs::Tracer.current_trace
  if trace && trace.prompt_version_id.nil?
    trace.update_column(:prompt_version_id, ver.id)
  end

  ver.render(variables)
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd /Users/anton/workspace/llm_logs && bundle exec rspec spec/models/llm_logs/prompt_spec.rb`
Expected: ALL PASS

- [ ] **Step 5: Run full test suite to verify no regressions**

Run: `cd /Users/anton/workspace/llm_logs && bundle exec rspec`
Expected: ALL PASS

- [ ] **Step 6: Commit**

```bash
cd /Users/anton/workspace/llm_logs
git add app/models/llm_logs/prompt.rb spec/models/llm_logs/prompt_spec.rb
git commit -m "feat: auto-capture prompt version on active trace in Prompt#build"
```

---

### Task 3: Routes and flash alert layout

**Files:**
- Modify: `config/routes.rb`
- Modify: `app/views/layouts/llm_logs/application.html.erb`

- [ ] **Step 1: Update routes**

Replace the contents of `config/routes.rb`:

```ruby
LlmLogs::Engine.routes.draw do
  root to: "traces#index"

  resources :traces, only: [:index, :show] do
    resources :spans, only: [:show]
  end

  resources :prompts do
    resources :versions, only: [:index, :show, :destroy], controller: "prompt_versions" do
      member do
        post :restore
      end
      collection do
        get :compare
      end
    end
  end
end
```

- [ ] **Step 2: Add alert flash rendering to layout**

In `app/views/layouts/llm_logs/application.html.erb`, add the alert block immediately after the notice block's closing `<% end %>` tag (after line 35), before the `<main>` tag:

```erb
<% if alert.present? %>
  <div class="mx-auto max-w-7xl px-4 sm:px-6 lg:px-8 mt-4">
    <div class="rounded-md bg-red-50 p-3 text-sm text-red-800 border border-red-200">
      <%= alert %>
    </div>
  </div>
<% end %>
```

- [ ] **Step 3: Verify app still loads**

Run: `cd /Users/anton/workspace/llm_logs && bundle exec rspec spec/requests/llm_logs/prompts_spec.rb`
Expected: ALL PASS

- [ ] **Step 4: Commit**

```bash
cd /Users/anton/workspace/llm_logs
git add config/routes.rb app/views/layouts/llm_logs/application.html.erb
git commit -m "feat: add version management routes and alert flash rendering"
```

---

### Task 4: Restore action

**Files:**
- Modify: `app/controllers/llm_logs/prompt_versions_controller.rb`
- Test: `spec/requests/llm_logs/prompt_versions_spec.rb` (create)

- [ ] **Step 1: Write the failing test for restore**

Create `spec/requests/llm_logs/prompt_versions_spec.rb`:

```ruby
require "spec_helper"

RSpec.describe "LlmLogs::PromptVersions", type: :request do
  let!(:prompt) { LlmLogs::Prompt.create!(slug: "test", name: "Test Prompt") }

  before do
    prompt.update_content!(messages: [{ "role" => "system", "content" => "v1 content" }], model: "gpt-4")
    prompt.update_content!(messages: [{ "role" => "system", "content" => "v2 content" }], model: "gpt-4o")
  end

  describe "GET /llm_logs/prompts/:prompt_id/versions" do
    it "renders the version history" do
      get "/llm_logs/prompts/#{prompt.id}/versions"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("v1")
      expect(response.body).to include("v2")
    end
  end

  describe "GET /llm_logs/prompts/:prompt_id/versions/:id" do
    it "renders the version detail" do
      version = prompt.version(1)
      get "/llm_logs/prompts/#{prompt.id}/versions/#{version.id}"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("v1 content")
    end
  end

  describe "POST /llm_logs/prompts/:prompt_id/versions/:id/restore" do
    it "creates a new version with the old content" do
      version_1 = prompt.version(1)

      expect {
        post "/llm_logs/prompts/#{prompt.id}/versions/#{version_1.id}/restore"
      }.to change(LlmLogs::PromptVersion, :count).by(1)

      expect(response).to redirect_to("/llm_logs/prompts/#{prompt.id}")

      new_current = prompt.reload.current_version
      expect(new_current.version_number).to eq(3)
      expect(new_current.messages.first["content"]).to eq("v1 content")
      expect(new_current.model).to eq("gpt-4")
      expect(new_current.changelog).to eq("Rollback to version 1")
    end

    it "restoring the current version creates a duplicate copy" do
      current = prompt.current_version

      expect {
        post "/llm_logs/prompts/#{prompt.id}/versions/#{current.id}/restore"
      }.to change(LlmLogs::PromptVersion, :count).by(1)

      new_current = prompt.reload.current_version
      expect(new_current.version_number).to eq(3)
      expect(new_current.messages.first["content"]).to eq("v2 content")
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /Users/anton/workspace/llm_logs && bundle exec rspec spec/requests/llm_logs/prompt_versions_spec.rb`
Expected: FAIL — restore action not found

- [ ] **Step 3: Implement restore action**

In `app/controllers/llm_logs/prompt_versions_controller.rb`, add the restore action:

```ruby
module LlmLogs
  class PromptVersionsController < ApplicationController
    def index
      @prompt = Prompt.find(params[:prompt_id])
      @versions = @prompt.versions.order(version_number: :desc)
    end

    def show
      @prompt = Prompt.find(params[:prompt_id])
      @version = @prompt.versions.find(params[:id])
    end

    def restore
      @prompt = Prompt.find(params[:prompt_id])
      version = @prompt.versions.find(params[:id])
      @prompt.rollback_to!(version.version_number)
      redirect_to prompt_path(@prompt), notice: "Restored to version #{version.version_number}."
    end
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd /Users/anton/workspace/llm_logs && bundle exec rspec spec/requests/llm_logs/prompt_versions_spec.rb`
Expected: ALL PASS

- [ ] **Step 5: Commit**

```bash
cd /Users/anton/workspace/llm_logs
git add app/controllers/llm_logs/prompt_versions_controller.rb spec/requests/llm_logs/prompt_versions_spec.rb
git commit -m "feat: add restore action to prompt versions controller"
```

---

### Task 5: Delete version action

**Files:**
- Modify: `app/controllers/llm_logs/prompt_versions_controller.rb`
- Test: `spec/requests/llm_logs/prompt_versions_spec.rb`

- [ ] **Step 1: Write the failing tests for destroy**

Add to `spec/requests/llm_logs/prompt_versions_spec.rb`, inside the top-level describe block:

```ruby
describe "DELETE /llm_logs/prompts/:prompt_id/versions/:id" do
  it "deletes a non-current version" do
    version_1 = prompt.version(1)

    expect {
      delete "/llm_logs/prompts/#{prompt.id}/versions/#{version_1.id}"
    }.to change(LlmLogs::PromptVersion, :count).by(-1)

    expect(response).to redirect_to("/llm_logs/prompts/#{prompt.id}/versions")
  end

  it "prevents deleting the current version" do
    current = prompt.current_version

    expect {
      delete "/llm_logs/prompts/#{prompt.id}/versions/#{current.id}"
    }.not_to change(LlmLogs::PromptVersion, :count)

    expect(response).to redirect_to("/llm_logs/prompts/#{prompt.id}/versions")
    follow_redirect!
    expect(response.body).to include("Cannot delete the current active version")
  end

  it "nullifies linked traces when version is deleted" do
    version_1 = prompt.version(1)
    trace = LlmLogs::Trace.create!(
      name: "test", started_at: Time.current, status: "completed",
      prompt_version: version_1
    )

    delete "/llm_logs/prompts/#{prompt.id}/versions/#{version_1.id}"
    expect(trace.reload.prompt_version_id).to be_nil
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /Users/anton/workspace/llm_logs && bundle exec rspec spec/requests/llm_logs/prompt_versions_spec.rb`
Expected: FAIL — destroy action not found

- [ ] **Step 3: Implement destroy action**

Add to `app/controllers/llm_logs/prompt_versions_controller.rb`, after the restore method:

```ruby
def destroy
  @prompt = Prompt.find(params[:prompt_id])
  version = @prompt.versions.find(params[:id])

  if version == @prompt.current_version
    redirect_to prompt_versions_path(@prompt), alert: "Cannot delete the current active version."
    return
  end

  version.destroy!
  redirect_to prompt_versions_path(@prompt), notice: "Version #{version.version_number} deleted."
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd /Users/anton/workspace/llm_logs && bundle exec rspec spec/requests/llm_logs/prompt_versions_spec.rb`
Expected: ALL PASS

- [ ] **Step 5: Commit**

```bash
cd /Users/anton/workspace/llm_logs
git add app/controllers/llm_logs/prompt_versions_controller.rb spec/requests/llm_logs/prompt_versions_spec.rb
git commit -m "feat: add delete version action with current-version guard"
```

---

### Task 6: Compare action

**Files:**
- Modify: `app/controllers/llm_logs/prompt_versions_controller.rb`
- Create: `app/views/llm_logs/prompt_versions/compare.html.erb`
- Test: `spec/requests/llm_logs/prompt_versions_spec.rb`

- [ ] **Step 1: Write the failing tests for compare**

Add to `spec/requests/llm_logs/prompt_versions_spec.rb`, inside the top-level describe block:

```ruby
describe "GET /llm_logs/prompts/:prompt_id/versions/compare" do
  it "renders a side-by-side diff of two versions" do
    get "/llm_logs/prompts/#{prompt.id}/versions/compare", params: { a: 1, b: 2 }
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("v1")
    expect(response.body).to include("v2")
    expect(response.body).to include("v1 content")
    expect(response.body).to include("v2 content")
  end

  it "redirects when a param is missing" do
    get "/llm_logs/prompts/#{prompt.id}/versions/compare", params: { a: 1 }
    expect(response).to redirect_to("/llm_logs/prompts/#{prompt.id}/versions")
    follow_redirect!
    expect(response.body).to include("Select two different versions")
  end

  it "redirects when both params are the same" do
    get "/llm_logs/prompts/#{prompt.id}/versions/compare", params: { a: 1, b: 1 }
    expect(response).to redirect_to("/llm_logs/prompts/#{prompt.id}/versions")
    follow_redirect!
    expect(response.body).to include("Select two different versions")
  end

  it "redirects when a version is not found" do
    get "/llm_logs/prompts/#{prompt.id}/versions/compare", params: { a: 1, b: 999 }
    expect(response).to redirect_to("/llm_logs/prompts/#{prompt.id}/versions")
    follow_redirect!
    expect(response.body).to include("Version not found")
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /Users/anton/workspace/llm_logs && bundle exec rspec spec/requests/llm_logs/prompt_versions_spec.rb`
Expected: FAIL — compare action not found

- [ ] **Step 3: Implement compare action**

Add to `app/controllers/llm_logs/prompt_versions_controller.rb`, after the destroy method:

```ruby
def compare
  @prompt = Prompt.find(params[:prompt_id])

  if params[:a].blank? || params[:b].blank? || params[:a] == params[:b]
    redirect_to prompt_versions_path(@prompt), alert: "Select two different versions to compare."
    return
  end

  @version_a = @prompt.versions.find_by(version_number: params[:a])
  @version_b = @prompt.versions.find_by(version_number: params[:b])

  unless @version_a && @version_b
    redirect_to prompt_versions_path(@prompt), alert: "Version not found."
    return
  end

  require "diffy"
  max_messages = [@version_a.messages.size, @version_b.messages.size].max
  @diffs = (0...max_messages).map do |i|
    msg_a = @version_a.messages[i]
    msg_b = @version_b.messages[i]
    role = (msg_a || msg_b)["role"]
    content_a = ERB::Util.html_escape(msg_a&.dig("content") || "")
    content_b = ERB::Util.html_escape(msg_b&.dig("content") || "")
    diff_html = Diffy::SplitDiff.new(content_a, content_b, format: :html_simple)
    { role: role, left: diff_html.left, right: diff_html.right }
  end
end
```

- [ ] **Step 4: Create compare view**

Create `app/views/llm_logs/prompt_versions/compare.html.erb`:

```erb
<div class="mb-6">
  <div class="flex items-center space-x-2 text-sm text-gray-500 mb-2">
    <%= link_to "Prompts", prompts_path, class: "text-indigo-600 hover:text-indigo-900" %>
    <span>/</span>
    <%= link_to @prompt.name, prompt_path(@prompt), class: "text-indigo-600 hover:text-indigo-900" %>
    <span>/</span>
    <span>Compare v<%= @version_a.version_number %> vs v<%= @version_b.version_number %></span>
  </div>
  <h1 class="text-2xl font-bold text-gray-900">
    Compare v<%= @version_a.version_number %> vs v<%= @version_b.version_number %>
  </h1>
</div>

<style>
  .diff del { background-color: #fecaca; text-decoration: none; }
  .diff ins { background-color: #bbf7d0; text-decoration: none; }
  .diff pre { white-space: pre-wrap; word-wrap: break-word; font-size: 0.875rem; }
</style>

<div class="space-y-6">
  <% @diffs.each do |diff| %>
    <div class="bg-white rounded-lg shadow-sm ring-1 ring-gray-900/5">
      <div class="px-4 py-3 border-b border-gray-200">
        <span class="text-xs font-medium text-gray-500 uppercase"><%= diff[:role] %></span>
      </div>
      <div class="grid grid-cols-2 divide-x divide-gray-200 diff">
        <div class="p-4">
          <div class="text-xs font-medium text-gray-400 mb-2">v<%= @version_a.version_number %></div>
          <pre class="font-mono"><%= raw diff[:left] %></pre>
        </div>
        <div class="p-4">
          <div class="text-xs font-medium text-gray-400 mb-2">v<%= @version_b.version_number %></div>
          <pre class="font-mono"><%= raw diff[:right] %></pre>
        </div>
      </div>
    </div>
  <% end %>
</div>
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd /Users/anton/workspace/llm_logs && bundle exec rspec spec/requests/llm_logs/prompt_versions_spec.rb`
Expected: ALL PASS

- [ ] **Step 6: Commit**

```bash
cd /Users/anton/workspace/llm_logs
git add app/controllers/llm_logs/prompt_versions_controller.rb app/views/llm_logs/prompt_versions/compare.html.erb spec/requests/llm_logs/prompt_versions_spec.rb
git commit -m "feat: add compare action with side-by-side diff view"
```

---

### Task 7: Version history UI — current badge, action buttons, checkboxes

**Files:**
- Modify: `app/views/llm_logs/prompt_versions/index.html.erb`
- Modify: `app/views/llm_logs/prompts/show.html.erb`

- [ ] **Step 1: Rewrite version history index with all new UI elements**

Replace the entire contents of `app/views/llm_logs/prompt_versions/index.html.erb`:

```erb
<div class="mb-6">
  <div class="flex items-center space-x-2 text-sm text-gray-500 mb-2">
    <%= link_to "Prompts", prompts_path, class: "text-indigo-600 hover:text-indigo-900" %>
    <span>/</span>
    <%= link_to @prompt.name, prompt_path(@prompt), class: "text-indigo-600 hover:text-indigo-900" %>
    <span>/</span>
    <span>Versions</span>
  </div>
  <h1 class="text-2xl font-bold text-gray-900">Version History: <%= @prompt.name %></h1>
</div>

<div id="compare-bar" class="mb-4 hidden">
  <a id="compare-link" href="#" class="inline-flex items-center bg-indigo-600 text-white px-4 py-2 rounded-md text-sm font-medium hover:bg-indigo-500">
    Compare
  </a>
</div>

<% current_version = @prompt.current_version %>

<div class="space-y-4">
  <% @versions.each do |version| %>
    <% is_current = version == current_version %>
    <div class="bg-white rounded-lg shadow-sm ring-1 ring-gray-900/5 p-4">
      <div class="flex items-center justify-between mb-3">
        <div class="flex items-center space-x-3">
          <input type="checkbox" class="compare-checkbox rounded border-gray-300 text-indigo-600"
                 value="<%= version.version_number %>" data-version="<%= version.version_number %>">
          <%= link_to prompt_version_path(@prompt, version), class: "text-lg font-semibold text-gray-900 hover:text-indigo-600" do %>
            v<%= version.version_number %>
          <% end %>
          <% if is_current %>
            <span class="inline-flex items-center rounded-full bg-green-100 px-2 py-0.5 text-xs font-medium text-green-800">Current</span>
          <% end %>
          <% if version.model.present? %>
            <span class="text-xs bg-gray-100 rounded-full px-2 py-0.5 text-gray-600"><%= version.model %></span>
          <% end %>
        </div>
        <div class="flex items-center space-x-3">
          <span class="text-sm text-gray-500"><%= version.created_at.strftime('%b %d, %Y %H:%M') %></span>
          <% unless is_current %>
            <%= button_to "Restore", restore_prompt_version_path(@prompt, version),
                method: :post,
                class: "text-sm text-indigo-600 hover:text-indigo-900",
                data: { turbo_confirm: "Are you sure you want to restore this as the current active prompt version?" } %>
            <%= button_to "Delete", prompt_version_path(@prompt, version),
                method: :delete,
                class: "text-sm text-red-600 hover:text-red-900",
                data: { turbo_confirm: "Are you sure you want to delete this version?" } %>
          <% end %>
        </div>
      </div>

      <% if version.changelog.present? %>
        <p class="text-sm text-gray-600 mb-3"><%= version.changelog %></p>
      <% end %>

      <div class="space-y-2">
        <% version.messages.each do |msg| %>
          <div class="rounded p-2 text-xs <%= msg['role'] == 'system' ? 'bg-yellow-50' : msg['role'] == 'user' ? 'bg-blue-50' : 'bg-gray-50' %>">
            <span class="font-medium text-gray-500 uppercase"><%= msg['role'] %>:</span>
            <span class="font-mono"><%= truncate(msg['content'], length: 120) %></span>
          </div>
        <% end %>
      </div>
    </div>
  <% end %>
</div>

<script>
  document.addEventListener("DOMContentLoaded", function() {
    var checkboxes = document.querySelectorAll(".compare-checkbox");
    var bar = document.getElementById("compare-bar");
    var link = document.getElementById("compare-link");
    var basePath = "<%= prompt_versions_path(@prompt) %>/compare";

    checkboxes.forEach(function(cb) {
      cb.addEventListener("change", updateCompare);
    });

    function updateCompare() {
      var checked = document.querySelectorAll(".compare-checkbox:checked");
      if (checked.length === 2) {
        var versions = Array.from(checked).map(function(cb) { return parseInt(cb.value); }).sort(function(a, b) { return a - b; });
        link.href = basePath + "?a=" + versions[0] + "&b=" + versions[1];
        link.textContent = "Compare v" + versions[0] + " vs v" + versions[1];
        bar.classList.remove("hidden");
      } else {
        bar.classList.add("hidden");
      }
    }
  });
</script>
```

- [ ] **Step 2: Add "Current" badge to prompt show sidebar**

In `app/views/llm_logs/prompts/show.html.erb`, find the version history sidebar section. In the `@versions.each` loop (around line 82), after the version number span, add the current badge. Replace:

```erb
<span class="text-sm font-medium text-gray-900">v<%= version.version_number %></span>
```

With:

```erb
<span class="text-sm font-medium text-gray-900">v<%= version.version_number %></span>
<% if version == @current_version %>
  <span class="inline-flex items-center rounded-full bg-green-100 px-1.5 py-0.5 text-xs font-medium text-green-800">Current</span>
<% end %>
```

- [ ] **Step 3: Run full test suite to verify no breakage**

Run: `cd /Users/anton/workspace/llm_logs && bundle exec rspec`
Expected: ALL PASS

- [ ] **Step 4: Commit**

```bash
cd /Users/anton/workspace/llm_logs
git add app/views/llm_logs/prompt_versions/index.html.erb app/views/llm_logs/prompts/show.html.erb
git commit -m "feat: add current badge, action buttons, and compare checkboxes to version UI"
```

---

### Task 8: Trace-to-version link in UI

**Files:**
- Modify: `app/views/llm_logs/traces/show.html.erb`
- Modify: `app/views/llm_logs/prompt_versions/show.html.erb`
- Modify: `app/controllers/llm_logs/traces_controller.rb`
- Modify: `app/views/llm_logs/traces/index.html.erb`
- Test: `spec/requests/llm_logs/traces_spec.rb`

- [ ] **Step 1: Write the failing test for trace show with prompt version link**

Add to `spec/requests/llm_logs/traces_spec.rb`, inside the `describe "GET /llm_logs/traces/:id"` block:

```ruby
it "shows prompt version link when present" do
  prompt = LlmLogs::Prompt.create!(slug: "test", name: "Test Prompt")
  prompt.update_content!(messages: [{ "role" => "user", "content" => "Hello" }])
  version = prompt.current_version
  trace.update!(prompt_version: version)

  get "/llm_logs/traces/#{trace.id}"
  expect(response).to have_http_status(:ok)
  expect(response.body).to include("Test Prompt")
  expect(response.body).to include("v1")
end
```

- [ ] **Step 2: Write the failing test for version show with trace count**

Add to `spec/requests/llm_logs/prompt_versions_spec.rb`, inside the `describe "GET /llm_logs/prompts/:prompt_id/versions/:id"` block:

```ruby
it "shows trace count when version has linked traces" do
  version = prompt.version(1)
  LlmLogs::Trace.create!(
    name: "test", started_at: Time.current, status: "completed",
    prompt_version: version
  )

  get "/llm_logs/prompts/#{prompt.id}/versions/#{version.id}"
  expect(response).to have_http_status(:ok)
  expect(response.body).to include("1 trace")
end
```

- [ ] **Step 3: Write the failing test for traces index filtered by prompt_version_id**

Add to `spec/requests/llm_logs/traces_spec.rb`, inside the `describe "GET /llm_logs"` block:

```ruby
it "filters traces by prompt_version_id and shows filter banner" do
  prompt = LlmLogs::Prompt.create!(slug: "test", name: "Test Prompt")
  prompt.update_content!(messages: [{ "role" => "user", "content" => "Hello" }])
  version = prompt.current_version
  trace.update!(prompt_version: version)

  other_trace = LlmLogs::Trace.create!(
    name: "other_trace", status: "completed",
    started_at: Time.current
  )

  get "/llm_logs", params: { prompt_version_id: version.id }
  expect(response).to have_http_status(:ok)
  expect(response.body).to include("test_trace")
  expect(response.body).not_to include("other_trace")
  expect(response.body).to include("Filtering by prompt:")
  expect(response.body).to include("Test Prompt")
  expect(response.body).to include("Clear filter")
end
```

- [ ] **Step 4: Run tests to verify they fail**

Run: `cd /Users/anton/workspace/llm_logs && bundle exec rspec spec/requests/llm_logs/traces_spec.rb spec/requests/llm_logs/prompt_versions_spec.rb`
Expected: FAIL

- [ ] **Step 5: Add prompt_version_id filter to traces controller**

In `app/controllers/llm_logs/traces_controller.rb`, update the `index` action to filter by prompt_version_id and load the filter version for the banner:

```ruby
def index
  @traces = Trace.recent
  @traces = @traces.by_status(params[:status]) if params[:status].present?
  if params[:prompt_version_id].present?
    @traces = @traces.where(prompt_version_id: params[:prompt_version_id])
    @filter_version = PromptVersion.find_by(id: params[:prompt_version_id])
  end
  @traces = @traces.page(params[:page]).per(50)
end
```

- [ ] **Step 6: Add prompt version link to trace show view**

In `app/views/llm_logs/traces/show.html.erb`, after the started_at line (line 12-13) and before the closing `</div>`, add:

```erb
<% if @trace.prompt_version.present? %>
  <p class="text-sm text-gray-500 mt-1">
    Prompt: <%= link_to "#{@trace.prompt_version.prompt.name} v#{@trace.prompt_version.version_number}",
      prompt_version_path(@trace.prompt_version.prompt, @trace.prompt_version),
      class: "text-indigo-600 hover:text-indigo-900" %>
  </p>
<% end %>
```

- [ ] **Step 7: Add trace count to prompt version show view**

In `app/views/llm_logs/prompt_versions/show.html.erb`, after the changelog line (line 12) and before the closing `</div>` of the header section, add:

```erb
<p class="text-sm text-gray-500 mt-1">
  <%= link_to pluralize(@version.traces.count, "trace"),
    traces_path(prompt_version_id: @version.id),
    class: "text-indigo-600 hover:text-indigo-900" %>
</p>
```

- [ ] **Step 8: Add prompt version filter banner to traces index**

In `app/views/llm_logs/traces/index.html.erb`, after the opening h1 line (line 2), add a banner that shows when filtering by prompt_version_id. Uses `@filter_version` set by the controller:

```erb
<% if @filter_version %>
  <p class="text-sm text-gray-500">
    Filtering by prompt: <span class="font-medium"><%= @filter_version.prompt.name %> v<%= @filter_version.version_number %></span>
    &middot; <%= link_to "Clear filter", traces_path, class: "text-indigo-600 hover:text-indigo-900" %>
  </p>
<% end %>
```

- [ ] **Step 9: Run tests to verify they pass**

Run: `cd /Users/anton/workspace/llm_logs && bundle exec rspec spec/requests/llm_logs/traces_spec.rb spec/requests/llm_logs/prompt_versions_spec.rb`
Expected: ALL PASS

- [ ] **Step 10: Run full test suite**

Run: `cd /Users/anton/workspace/llm_logs && bundle exec rspec`
Expected: ALL PASS

- [ ] **Step 11: Commit**

```bash
cd /Users/anton/workspace/llm_logs
git add app/controllers/llm_logs/traces_controller.rb app/views/llm_logs/traces/show.html.erb app/views/llm_logs/traces/index.html.erb app/views/llm_logs/prompt_versions/show.html.erb spec/requests/llm_logs/traces_spec.rb spec/requests/llm_logs/prompt_versions_spec.rb
git commit -m "feat: add trace-to-version link in UI with filtering"
```

---

### Task 9: Final integration test and cleanup

**Files:**
- Test: full suite

- [ ] **Step 1: Run the full test suite**

Run: `cd /Users/anton/workspace/llm_logs && bundle exec rspec`
Expected: ALL PASS

- [ ] **Step 2: Verify routes are correct**

Run: `cd /Users/anton/workspace/llm_logs && RAILS_ENV=test bundle exec rails routes -g version`
Expected: Shows all version routes including restore, destroy, compare

- [ ] **Step 3: Commit any remaining changes**

If there are any uncommitted changes, commit them:

```bash
cd /Users/anton/workspace/llm_logs
git status
# If anything needs committing:
git add -A && git commit -m "chore: final cleanup for prompt version controls"
```
