# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 6) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "llm_logs_prompt_versions", force: :cascade do |t|
    t.text "changelog"
    t.datetime "created_at", null: false
    t.jsonb "default_variables", default: {}
    t.jsonb "messages", default: [], null: false
    t.string "model"
    t.jsonb "model_params", default: {}
    t.bigint "prompt_id", null: false
    t.datetime "updated_at", null: false
    t.integer "version_number", null: false
    t.index ["prompt_id", "version_number"], name: "idx_llm_logs_prompt_versions_on_prompt_and_version", unique: true
    t.index ["prompt_id"], name: "index_llm_logs_prompt_versions_on_prompt_id"
  end

  create_table "llm_logs_prompts", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.string "name", null: false
    t.string "slug", null: false
    t.datetime "updated_at", null: false
    t.index ["slug"], name: "index_llm_logs_prompts_on_slug", unique: true
  end

  create_table "llm_logs_spans", force: :cascade do |t|
    t.integer "cached_tokens"
    t.datetime "completed_at"
    t.decimal "cost", precision: 10, scale: 6
    t.datetime "created_at", null: false
    t.float "duration_ms"
    t.text "error_message"
    t.jsonb "input"
    t.integer "input_tokens"
    t.jsonb "metadata", default: {}
    t.string "model"
    t.string "name", null: false
    t.jsonb "output"
    t.integer "output_tokens"
    t.bigint "parent_span_id"
    t.string "provider"
    t.string "span_type", null: false
    t.datetime "started_at", null: false
    t.string "status", default: "ok", null: false
    t.bigint "trace_id", null: false
    t.datetime "updated_at", null: false
    t.index ["parent_span_id"], name: "index_llm_logs_spans_on_parent_span_id"
    t.index ["span_type"], name: "index_llm_logs_spans_on_span_type"
    t.index ["started_at"], name: "index_llm_logs_spans_on_started_at"
    t.index ["trace_id"], name: "index_llm_logs_spans_on_trace_id"
  end

  create_table "llm_logs_traces", force: :cascade do |t|
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.float "duration_ms"
    t.jsonb "metadata", default: {}
    t.string "name", null: false
    t.integer "spans_count", default: 0, null: false
    t.datetime "started_at", null: false
    t.string "status", default: "running", null: false
    t.decimal "total_cost", precision: 10, scale: 6, default: "0.0"
    t.integer "total_cached_tokens", default: 0, null: false
    t.integer "total_input_tokens", default: 0
    t.integer "total_output_tokens", default: 0
    t.datetime "updated_at", null: false
    t.index ["started_at"], name: "index_llm_logs_traces_on_started_at"
    t.index ["status"], name: "index_llm_logs_traces_on_status"
  end

  add_foreign_key "llm_logs_prompt_versions", "llm_logs_prompts", column: "prompt_id"
  add_foreign_key "llm_logs_spans", "llm_logs_spans", column: "parent_span_id"
  add_foreign_key "llm_logs_spans", "llm_logs_traces", column: "trace_id"
end
