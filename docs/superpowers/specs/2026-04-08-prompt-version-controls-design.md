# Prompt Version Controls Design

## Problem

Users cannot compare versions, restore a previous version, or safely delete versions with confirmation. There is also no link between log entries (traces) and the prompt version that generated them, making it impossible to correlate prompt changes with observed behavior.

## Scope

All changes are in the llm_logs gem. No host-app changes required.

## Data Layer

### Migration: Add prompt_version_id to traces

- Add nullable `bigint` FK column `prompt_version_id` on `llm_logs_traces` referencing `llm_logs_prompt_versions`
- FK uses `ON DELETE SET NULL` — if a version is deleted, traces keep existing but lose the version link (preserving audit data)
- Add index on `prompt_version_id`

### Model changes

**Trace:**
- `belongs_to :prompt_version, class_name: "LlmLogs::PromptVersion", optional: true`

**PromptVersion:**
- `has_many :traces, class_name: "LlmLogs::Trace", dependent: :nullify`

### Auto-capture

In `Prompt#build` only, after resolving the version, check `LlmLogs::Tracer.current_trace`. If a trace is active and its `prompt_version_id` is nil, set it to the resolved version's ID and save.

Auto-capture is NOT added to `current_version` — that is a reader/query method and adding a database write side-effect would violate least surprise (e.g., calling it in a view or console would mutate the trace).

Only the first prompt version used per trace is captured. If a trace calls `prompt_a.build(...)` then `prompt_b.build(...)`, only prompt_a is linked. This is intentional: one trace = one logical operation = one prompt.

This means any host app that calls `prompt.build(...)` inside a `LlmLogs.trace` block automatically gets the link — zero caller changes.

### New gem dependency

- `diffy` (~> 3.4) for server-side diff computation

## Routes

```ruby
resources :prompts do
  resources :versions, controller: "prompt_versions" do
    member do
      post :restore
    end
    collection do
      get :compare
    end
  end
end
```

**Version routes:**
| Method | Path | Action |
|--------|------|--------|
| GET | `/prompts/:prompt_id/versions` | index (existing) |
| GET | `/prompts/:prompt_id/versions/:id` | show (existing) |
| DELETE | `/prompts/:prompt_id/versions/:id` | destroy (new) |
| POST | `/prompts/:prompt_id/versions/:id/restore` | restore (new) |
| GET | `/prompts/:prompt_id/versions/compare?a=X&b=Y` | compare (new) |

## Version Management Actions

### Restore

- `PromptVersionsController#restore`
- Uses existing `Prompt#rollback_to!(version_number)` — creates a new version with old content, changelog "Rollback to version N"
- Confirmation via `data-turbo-confirm`: "Are you sure you want to restore this as the current active prompt version?"
- Redirects to prompt show page with flash notice

### Delete version

- `PromptVersionsController#destroy`
- Cannot delete the current active version (highest version_number) — returns error flash. The current version is always the highest version_number. Preventing its deletion ensures `Prompt#build` continues to return the same content. Deleting any other version is safe.
- Traces linked to a deleted version keep existing but lose the version link (FK is `ON DELETE SET NULL`)
- Confirmation via `data-turbo-confirm`: "Are you sure you want to delete this version?"
- Redirects to version history

### Delete prompt (enhancement)

- Already exists in `PromptsController#destroy`
- Update `data-turbo-confirm` copy to: "Are you sure you want to delete this prompt?"
- Cascade via `dependent: :destroy` already handles versions

### "Current Version" badge

- On version history and prompt show sidebar, the current version gets a green badge: `Current`
- Current version row hides Delete and Restore buttons

## Compare Mode

### UI flow

1. Version history page: each version row gets a checkbox with the version's `version_number` as value
2. Stimulus `compare-controller` tracks checked boxes:
   - Exactly 2 checked: "Compare" button appears, showing "Compare vX vs vY"
   - Fewer or more than 2 checked: button hidden/disabled (checking a 3rd box hides the button)
3. Clicking "Compare" navigates to compare route with version_numbers as query params (`?a=X&b=Y`). The lower version_number is always `a` (left side) regardless of check order

### Compare view

- Breadcrumb: Prompts / [name] / Compare vA vs vB
- For each message role present in either version:
  - Header showing the role
  - Side-by-side layout: version A on left, version B on right
  - Message content is HTML-escaped before passing to Diffy to prevent XSS: `Diffy::Diff.new(ERB::Util.html_escape(text_a), ERB::Util.html_escape(text_b)).to_s(:html_simple)`
  - Diff output produces `<ins>` and `<del>` tags, rendered with `raw` in the view
  - `del` styled with red background, `ins` with green background
- Messages matched by index and role. Extra messages in one version show as entirely added/removed

### Compare error handling

- If `a` or `b` param is missing, or both are the same, redirect back to version index with flash error
- If a version_number is not found for the prompt, redirect back with flash error

### Diff computation

- Controller iterates messages by index, diffs each content pair with Diffy
- No new model or service class needed

## Trace-to-Version Link in UI

### Trace show page

- If `trace.prompt_version` is present, show: "Prompt: [name] v[N]" linked to prompt version show page
- If not present, no visual change

### Prompt version show page

- "Used in N traces" count, linked to filtered traces index

### Traces index

- Accept optional `prompt_version_id` query param to filter traces by version

## Design decisions

### No pagination on version history

The version history page does not paginate. Prompts are expected to have tens of versions, not thousands. The checkbox compare flow requires selecting across all versions, which breaks with pagination. If this becomes a performance issue, it can be addressed later.

### Authorization

Authorization is out of scope for this feature. The gem's existing controllers have no auth checks — host apps are expected to restrict access to the mounted engine via routing constraints or middleware (e.g., `authenticate :admin_user` in the mount block). The new destructive actions (delete, restore) inherit whatever access control the host app applies to the engine mount point.

## Files changed

### New files
- `db/migrate/005_add_prompt_version_to_traces.rb`
- `app/views/llm_logs/prompt_versions/compare.html.erb`
- `app/javascript/llm_logs/compare_controller.js` (Stimulus)

### Modified files
- `llm_logs.gemspec` — add `diffy` dependency
- `app/models/llm_logs/trace.rb` — add `belongs_to :prompt_version`
- `app/models/llm_logs/prompt_version.rb` — add `has_many :traces`
- `app/models/llm_logs/prompt.rb` — auto-capture in `build`
- `config/routes.rb` — add destroy, restore, compare routes
- `app/controllers/llm_logs/prompt_versions_controller.rb` — add restore, destroy, compare actions
- `app/controllers/llm_logs/traces_controller.rb` — add prompt_version_id filter
- `app/views/llm_logs/prompt_versions/index.html.erb` — checkboxes, current badge, action buttons
- `app/views/llm_logs/prompt_versions/show.html.erb` — trace count link
- `app/views/llm_logs/prompts/show.html.erb` — current badge in sidebar, update confirm copy
- `app/views/llm_logs/traces/show.html.erb` — prompt version link
