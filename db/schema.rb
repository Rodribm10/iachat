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

ActiveRecord::Schema[7.2].define(version: 2026_08_22_154638) do
  # These extensions should be enabled to support this database
  enable_extension "pg_stat_statements"
  enable_extension "pg_trgm"
  enable_extension "pgcrypto"
  enable_extension "plpgsql"
  enable_extension "unaccent"
  enable_extension "vector"

  # Custom SQL functions (required before index creation)
  execute <<~SQL
    CREATE OR REPLACE FUNCTION f_unaccent(text)
      RETURNS text LANGUAGE sql IMMUTABLE PARALLEL SAFE STRICT
      AS $func$ SELECT public.unaccent('public.unaccent', $1) $func$
  SQL

  create_table "access_tokens", force: :cascade do |t|
    t.string "owner_type"
    t.bigint "owner_id"
    t.string "token"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.index ["owner_type", "owner_id"], name: "index_access_tokens_on_owner_type_and_owner_id"
    t.index ["token"], name: "index_access_tokens_on_token", unique: true
  end

  create_table "account_saml_settings", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "sso_url"
    t.text "certificate"
    t.string "sp_entity_id"
    t.string "idp_entity_id"
    t.json "role_mappings", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_account_saml_settings_on_account_id"
  end

  create_table "account_users", force: :cascade do |t|
    t.bigint "account_id"
    t.bigint "user_id"
    t.integer "role", default: 0
    t.bigint "inviter_id"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.datetime "active_at", precision: nil
    t.integer "availability", default: 0, null: false
    t.boolean "auto_offline", default: true, null: false
    t.bigint "custom_role_id"
    t.bigint "agent_capacity_policy_id"
    t.index ["account_id", "user_id"], name: "uniq_user_id_per_account_id", unique: true
    t.index ["account_id"], name: "index_account_users_on_account_id"
    t.index ["agent_capacity_policy_id"], name: "index_account_users_on_agent_capacity_policy_id"
    t.index ["custom_role_id"], name: "index_account_users_on_custom_role_id"
    t.index ["user_id"], name: "index_account_users_on_user_id"
  end

  create_table "accounts", id: :serial, force: :cascade do |t|
    t.string "name", null: false
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.integer "locale", default: 0
    t.string "domain", limit: 100
    t.string "support_email", limit: 100
    t.bigint "feature_flags", default: 0, null: false
    t.integer "auto_resolve_duration"
    t.jsonb "limits", default: {}
    t.jsonb "custom_attributes", default: {}
    t.integer "status", default: 0
    t.jsonb "internal_attributes", default: {}, null: false
    t.jsonb "settings", default: {}
    t.bigint "feature_flags_ext_1", default: 0, null: false
    t.index ["status"], name: "index_accounts_on_status"
  end

  create_table "action_mailbox_inbound_emails", force: :cascade do |t|
    t.integer "status", default: 0, null: false
    t.string "message_id", null: false
    t.string "message_checksum", null: false
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.index ["message_id", "message_checksum"], name: "index_action_mailbox_inbound_emails_uniqueness", unique: true
  end

  create_table "active_storage_attachments", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", precision: nil, null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", precision: nil, null: false
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "agent_bot_inboxes", force: :cascade do |t|
    t.integer "inbox_id"
    t.integer "agent_bot_id"
    t.integer "status", default: 0
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.integer "account_id"
  end

  create_table "agent_bots", force: :cascade do |t|
    t.string "name"
    t.string "description"
    t.string "outgoing_url"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.bigint "account_id"
    t.integer "bot_type", default: 0
    t.jsonb "bot_config", default: {}
    t.string "secret"
    t.index ["account_id"], name: "index_agent_bots_on_account_id"
  end

  create_table "agent_capacity_policies", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "name", limit: 255, null: false
    t.text "description"
    t.jsonb "exclusion_rules", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_agent_capacity_policies_on_account_id"
  end

  create_table "agent_sessions", force: :cascade do |t|
    t.integer "session_type", null: false
    t.string "subject_type", null: false
    t.bigint "subject_id", null: false
    t.string "result_type"
    t.bigint "result_id"
    t.bigint "account_id", null: false
    t.bigint "assistant_id", null: false
    t.bigint "user_id"
    t.string "llm_model"
    t.float "credits_consumed"
    t.jsonb "faq_ids", default: []
    t.jsonb "document_ids", default: []
    t.jsonb "scenario_ids", default: []
    t.jsonb "run_context", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.jsonb "cited_document_ids", default: [], null: false
    t.jsonb "used_faq_ids", default: [], null: false
    t.index ["account_id", "result_type", "result_id"], name: "idx_on_account_id_result_type_result_id_ca66c00cd7"
    t.index ["account_id", "session_type", "created_at"], name: "idx_on_account_id_session_type_created_at_c20a14bd4e"
    t.index ["account_id", "subject_type", "subject_id"], name: "idx_on_account_id_subject_type_subject_id_6d60963b3d"
    t.index ["account_id"], name: "index_agent_sessions_on_account_id"
    t.index ["assistant_id"], name: "index_agent_sessions_on_assistant_id"
    t.index ["cited_document_ids"], name: "index_agent_sessions_on_cited_document_ids", using: :gin
    t.index ["document_ids"], name: "index_agent_sessions_on_document_ids", using: :gin
    t.index ["used_faq_ids"], name: "index_agent_sessions_on_used_faq_ids", using: :gin
    t.index ["user_id"], name: "index_agent_sessions_on_user_id"
  end

  create_table "applied_slas", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "sla_policy_id", null: false
    t.bigint "conversation_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "sla_status", default: 0
    t.datetime "completed_at"
    t.index ["account_id", "sla_policy_id", "conversation_id"], name: "index_applied_slas_on_account_sla_policy_conversation", unique: true
    t.index ["account_id"], name: "index_applied_slas_on_account_id"
    t.index ["conversation_id"], name: "index_applied_slas_on_conversation_id"
    t.index ["sla_policy_id"], name: "index_applied_slas_on_sla_policy_id"
  end

  create_table "article_embeddings", force: :cascade do |t|
    t.bigint "article_id", null: false
    t.text "term", null: false
    t.vector "embedding", limit: 1536
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["embedding"], name: "index_article_embeddings_on_embedding", using: :ivfflat
  end

  create_table "articles", force: :cascade do |t|
    t.integer "account_id", null: false
    t.integer "portal_id", null: false
    t.integer "category_id"
    t.integer "folder_id"
    t.string "title"
    t.text "description"
    t.text "content"
    t.integer "status"
    t.integer "views"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.bigint "author_id"
    t.bigint "associated_article_id"
    t.jsonb "meta", default: {}
    t.string "slug", null: false
    t.integer "position"
    t.string "locale", default: "en", null: false
    t.string "draft_title"
    t.text "draft_content"
    t.index ["account_id"], name: "index_articles_on_account_id"
    t.index ["associated_article_id"], name: "index_articles_on_associated_article_id"
    t.index ["author_id"], name: "index_articles_on_author_id"
    t.index ["portal_id"], name: "index_articles_on_portal_id"
    t.index ["slug"], name: "index_articles_on_slug", unique: true
    t.index ["status"], name: "index_articles_on_status"
    t.index ["views"], name: "index_articles_on_views"
  end

  create_table "assignment_policies", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "name", limit: 255, null: false
    t.text "description"
    t.integer "assignment_order", default: 0, null: false
    t.integer "conversation_priority", default: 0, null: false
    t.integer "fair_distribution_limit", default: 100, null: false
    t.integer "fair_distribution_window", default: 3600, null: false
    t.boolean "enabled", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "exclude_older_than_hours", default: 168
    t.index ["account_id", "name"], name: "index_assignment_policies_on_account_id_and_name", unique: true
    t.index ["account_id"], name: "index_assignment_policies_on_account_id"
    t.index ["enabled"], name: "index_assignment_policies_on_enabled"
  end

  create_table "attachments", id: :serial, force: :cascade do |t|
    t.integer "file_type", default: 0
    t.string "external_url"
    t.float "coordinates_lat", default: 0.0
    t.float "coordinates_long", default: 0.0
    t.integer "message_id", null: false
    t.integer "account_id", null: false
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.string "fallback_title"
    t.string "extension"
    t.jsonb "meta", default: {}
    t.index ["account_id"], name: "index_attachments_on_account_id"
    t.index ["message_id"], name: "index_attachments_on_message_id"
  end

  create_table "audits", force: :cascade do |t|
    t.bigint "auditable_id"
    t.string "auditable_type"
    t.bigint "associated_id"
    t.string "associated_type"
    t.bigint "user_id"
    t.string "user_type"
    t.string "username"
    t.string "action"
    t.jsonb "audited_changes"
    t.integer "version", default: 0
    t.string "comment"
    t.string "remote_address"
    t.string "request_uuid"
    t.datetime "created_at", precision: nil
    t.index ["associated_type", "associated_id", "created_at"], name: "index_audits_on_associated_and_created_at"
    t.index ["associated_type", "associated_id"], name: "associated_index"
    t.index ["auditable_type", "auditable_id", "version"], name: "auditable_index"
    t.index ["created_at"], name: "index_audits_on_created_at"
    t.index ["request_uuid"], name: "index_audits_on_request_uuid"
    t.index ["user_id", "user_type"], name: "user_index"
  end

  create_table "automation_rule_pending_executions", force: :cascade do |t|
    t.bigint "automation_rule_id", null: false
    t.bigint "conversation_id", null: false
    t.bigint "account_id", null: false
    t.bigint "message_id"
    t.datetime "due_at", null: false
    t.string "episode_key", null: false
    t.integer "status", default: 0, null: false
    t.string "skip_reason"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_automation_rule_pending_executions_on_account_id"
    t.index ["automation_rule_id", "conversation_id", "episode_key"], name: "uniq_automation_pending_execution_episode", unique: true
    t.index ["automation_rule_id"], name: "index_automation_rule_pending_executions_on_automation_rule_id"
    t.index ["conversation_id"], name: "index_automation_rule_pending_executions_on_conversation_id"
    t.index ["status", "due_at"], name: "index_automation_rule_pending_executions_on_status_and_due_at"
    t.index ["status", "updated_at"], name: "index_automation_pending_executions_on_status_and_updated_at"
  end

  create_table "automation_rules", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "name", null: false
    t.text "description"
    t.string "event_name", null: false
    t.jsonb "conditions", default: "{}", null: false
    t.jsonb "actions", default: "{}", null: false
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.boolean "active", default: true, null: false
    t.integer "execution_delay"
    t.index ["account_id"], name: "index_automation_rules_on_account_id"
  end

  create_table "calls", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "inbox_id", null: false
    t.bigint "conversation_id", null: false
    t.bigint "contact_id", null: false
    t.bigint "message_id"
    t.bigint "accepted_by_agent_id"
    t.string "provider_call_id", null: false
    t.integer "provider", default: 0, null: false
    t.integer "direction", null: false
    t.string "status", default: "ringing", null: false
    t.datetime "started_at"
    t.integer "duration_seconds"
    t.string "end_reason"
    t.jsonb "meta", default: {}
    t.text "transcript"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "contact_id"], name: "index_calls_on_account_id_and_contact_id"
    t.index ["account_id", "conversation_id"], name: "index_calls_on_account_id_and_conversation_id"
    t.index ["account_id", "created_at"], name: "index_calls_on_account_id_and_created_at"
    t.index ["message_id"], name: "index_calls_on_message_id"
    t.index ["provider", "provider_call_id"], name: "index_calls_on_provider_and_provider_call_id", unique: true
  end

  create_table "campaign_recipients", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "campaign_id", null: false
    t.bigint "contact_id", null: false
    t.bigint "inbox_id", null: false
    t.string "source_id"
    t.integer "status", default: 0, null: false
    t.string "error_code"
    t.string "error_title"
    t.text "error_message"
    t.text "message_content"
    t.datetime "sent_at"
    t.datetime "delivered_at"
    t.datetime "read_at"
    t.datetime "failed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "campaign_id"], name: "index_campaign_recipients_on_account_id_and_campaign_id"
    t.index ["account_id"], name: "index_campaign_recipients_on_account_id"
    t.index ["campaign_id", "contact_id"], name: "index_campaign_recipients_on_campaign_id_and_contact_id", unique: true
    t.index ["campaign_id", "status"], name: "index_campaign_recipients_on_campaign_id_and_status"
    t.index ["campaign_id"], name: "index_campaign_recipients_on_campaign_id"
    t.index ["contact_id"], name: "index_campaign_recipients_on_contact_id"
    t.index ["inbox_id"], name: "index_campaign_recipients_on_inbox_id"
    t.index ["source_id"], name: "index_campaign_recipients_on_source_id", unique: true, where: "(source_id IS NOT NULL)"
  end

  create_table "campaigns", force: :cascade do |t|
    t.integer "display_id", null: false
    t.string "title", null: false
    t.text "description"
    t.text "message", null: false
    t.integer "sender_id"
    t.boolean "enabled", default: true
    t.bigint "account_id", null: false
    t.bigint "inbox_id", null: false
    t.jsonb "trigger_rules", default: {}
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.integer "campaign_type", default: 0, null: false
    t.integer "campaign_status", default: 0, null: false
    t.jsonb "audience", default: []
    t.datetime "scheduled_at", precision: nil
    t.boolean "trigger_only_during_business_hours", default: false
    t.jsonb "template_params"
    t.datetime "started_at"
    t.datetime "completed_at"
    t.index ["account_id"], name: "index_campaigns_on_account_id"
    t.index ["campaign_status"], name: "index_campaigns_on_campaign_status"
    t.index ["campaign_type"], name: "index_campaigns_on_campaign_type"
    t.index ["inbox_id"], name: "index_campaigns_on_inbox_id"
    t.index ["scheduled_at"], name: "index_campaigns_on_scheduled_at"
  end

  create_table "canned_responses", id: :serial, force: :cascade do |t|
    t.integer "account_id", null: false
    t.string "short_code"
    t.text "content"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
  end

  create_table "captain_assistant_responses", force: :cascade do |t|
    t.string "question", null: false
    t.text "answer", null: false
    t.vector "embedding", limit: 1536
    t.bigint "assistant_id", null: false
    t.bigint "documentable_id"
    t.bigint "account_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "status", default: 1, null: false
    t.string "documentable_type"
    t.datetime "trial_until"
    t.string "source"
    t.string "triage_reason"
    t.jsonb "judge_verdict", default: {}
    t.datetime "promoted_at"
    t.datetime "retired_at"
    t.string "retired_reason"
    t.boolean "edited", default: false, null: false
    t.index ["account_id"], name: "index_captain_assistant_responses_on_account_id"
    t.index ["assistant_id"], name: "index_captain_assistant_responses_on_assistant_id"
    t.index ["documentable_id", "documentable_type"], name: "idx_cap_asst_resp_on_documentable"
    t.index ["embedding"], name: "vector_idx_knowledge_entries_embedding", using: :ivfflat
    t.index ["source"], name: "idx_cap_asst_resp_on_source"
    t.index ["status"], name: "index_captain_assistant_responses_on_status"
    t.index ["trial_until"], name: "idx_cap_asst_resp_on_trial_until", where: "(trial_until IS NOT NULL)"
  end

  create_table "captain_assistants", force: :cascade do |t|
    t.string "name", null: false
    t.bigint "account_id", null: false
    t.text "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.jsonb "config", default: {}, null: false
    t.jsonb "response_guidelines", default: []
    t.jsonb "guardrails", default: []
    t.string "llm_provider", default: "openai"
    t.string "llm_model", default: "gpt-3.5-turbo"
    t.text "api_key"
    t.jsonb "handoff_webhook_config", default: {}
    t.text "orchestrator_prompt"
    t.string "engine", default: "captain_interno", null: false
    t.string "hermes_profile_name"
    t.string "hermes_webhook_base_url"
    t.string "hermes_subscription_secret"
    t.integer "hermes_port"
    t.bigint "parent_assistant_id"
    t.bigint "captain_unit_id"
    t.index ["account_id"], name: "index_captain_assistants_on_account_id"
    t.index ["captain_unit_id"], name: "index_captain_assistants_on_captain_unit_id"
    t.index ["engine"], name: "index_captain_assistants_on_engine"
    t.index ["hermes_port"], name: "idx_captain_assistants_hermes_port_unique", unique: true, where: "(hermes_port IS NOT NULL)"
    t.index ["parent_assistant_id"], name: "index_captain_assistants_on_parent_assistant_id"
  end

  create_table "captain_brands", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "name", null: false
    t.jsonb "suite_categories", default: [], null: false
    t.jsonb "stay_durations", default: [], null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.jsonb "suite_images", default: {}, null: false
    t.jsonb "suite_descriptions", default: {}, null: false
    t.jsonb "pricing_page_config", default: {}, null: false
    t.jsonb "suite_keywords"
    t.index ["account_id"], name: "index_captain_brands_on_account_id"
  end

  create_table "captain_codex_credentials", force: :cascade do |t|
    t.text "access_token", null: false
    t.text "refresh_token", null: false
    t.datetime "expires_at", null: false
    t.datetime "last_refresh_at"
    t.string "chatgpt_account_id"
    t.string "chatgpt_plan_type"
    t.string "email"
    t.string "status", default: "active", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["expires_at"], name: "index_captain_codex_credentials_on_expires_at"
    t.index ["status"], name: "index_captain_codex_credentials_on_status"
  end

  create_table "captain_conversation_insights", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "captain_unit_id"
    t.date "period_start", null: false
    t.date "period_end", null: false
    t.string "status", default: "pending", null: false
    t.jsonb "payload"
    t.integer "conversations_count", default: 0
    t.integer "messages_count", default: 0
    t.integer "llm_tokens_used"
    t.datetime "generated_at", precision: nil
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "inbox_id"
    t.index ["account_id", "status"], name: "index_captain_conversation_insights_on_account_id_and_status"
    t.index ["account_id"], name: "index_captain_conversation_insights_on_account_id"
    t.index ["captain_unit_id", "inbox_id", "period_start", "period_end"], name: "idx_captain_insights_on_unit_inbox_period", unique: true
    t.index ["captain_unit_id"], name: "index_captain_conversation_insights_on_captain_unit_id"
    t.index ["inbox_id"], name: "index_captain_conversation_insights_on_inbox_id"
  end

  create_table "captain_custom_tools", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "slug", null: false
    t.string "title", null: false
    t.text "description"
    t.string "http_method", default: "GET", null: false
    t.text "endpoint_url", null: false
    t.text "request_template"
    t.text "response_template"
    t.string "auth_type", default: "none"
    t.jsonb "auth_config", default: {}
    t.jsonb "param_schema", default: []
    t.boolean "enabled", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "slug"], name: "index_captain_custom_tools_on_account_id_and_slug", unique: true
    t.index ["account_id"], name: "index_captain_custom_tools_on_account_id"
  end

  create_table "captain_documents", force: :cascade do |t|
    t.string "name"
    t.text "external_link", null: false
    t.text "content"
    t.bigint "assistant_id", null: false
    t.bigint "account_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "status", default: 0, null: false
    t.jsonb "metadata", default: {}
    t.integer "sync_status"
    t.datetime "last_synced_at"
    t.datetime "last_sync_attempted_at"
    t.index "assistant_id, md5(external_link)", name: "idx_captain_documents_on_assistant_id_and_external_link_md5", unique: true
    t.index ["account_id", "assistant_id", "sync_status", "last_synced_at"], name: "idx_captain_documents_on_account_assistant_sync_stats"
    t.index ["account_id", "sync_status"], name: "index_captain_documents_on_account_id_and_sync_status"
    t.index ["account_id"], name: "index_captain_documents_on_account_id"
    t.index ["assistant_id"], name: "index_captain_documents_on_assistant_id"
    t.index ["status"], name: "index_captain_documents_on_status"
  end

  create_table "captain_faq_observations", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "conversation_id", null: false
    t.bigint "faq_suggestion_id"
    t.string "generated_question", null: false
    t.text "generated_answer", null: false
    t.string "language", default: "en", null: false
    t.integer "status", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_captain_faq_observations_on_account_id"
    t.index ["conversation_id", "faq_suggestion_id"], name: "idx_captain_faq_observations_on_conversation_and_suggestion", unique: true, where: "(faq_suggestion_id IS NOT NULL)"
    t.index ["conversation_id"], name: "index_captain_faq_observations_on_conversation_id"
    t.index ["faq_suggestion_id"], name: "index_captain_faq_observations_on_faq_suggestion_id"
  end

  create_table "captain_faq_suggestions", force: :cascade do |t|
    t.string "question", null: false
    t.text "answer", null: false
    t.vector "embedding", limit: 1536
    t.bigint "assistant_id", null: false
    t.bigint "account_id", null: false
    t.string "language", default: "en", null: false
    t.integer "source_count", default: 0, null: false
    t.integer "status", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "assistant_id", "status", "language"], name: "idx_cap_faq_suggestions_on_account_assistant_status_language"
    t.index ["account_id"], name: "index_captain_faq_suggestions_on_account_id"
    t.index ["assistant_id"], name: "index_captain_faq_suggestions_on_assistant_id"
    t.index ["embedding"], name: "vector_idx_captain_faq_suggestions_embedding", opclass: :vector_cosine_ops, using: :ivfflat
  end

  create_table "captain_feedback_logs", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "inbox_id", null: false
    t.bigint "conversation_id", null: false
    t.bigint "assistant_id", null: false
    t.bigint "contact_id", null: false
    t.string "sentiment", null: false
    t.string "handoff_trigger"
    t.text "original_message"
    t.text "clarified_issue"
    t.integer "clarification_rounds", default: 0
    t.string "category"
    t.jsonb "subcategories", default: []
    t.jsonb "metadata", default: {}
    t.boolean "resolved", default: false
    t.datetime "resolved_at"
    t.bigint "resolved_by_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "created_at"], name: "index_captain_feedback_logs_on_account_id_and_created_at"
    t.index ["account_id"], name: "index_captain_feedback_logs_on_account_id"
    t.index ["assistant_id"], name: "index_captain_feedback_logs_on_assistant_id"
    t.index ["conversation_id"], name: "index_captain_feedback_logs_on_conversation_id"
    t.index ["created_at"], name: "index_captain_feedback_logs_on_created_at"
    t.index ["handoff_trigger"], name: "index_captain_feedback_logs_on_handoff_trigger"
    t.index ["inbox_id"], name: "index_captain_feedback_logs_on_inbox_id"
    t.index ["sentiment"], name: "index_captain_feedback_logs_on_sentiment"
  end

  create_table "captain_gallery_items", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "captain_unit_id"
    t.bigint "created_by_id"
    t.string "suite_category", null: false
    t.string "suite_number", null: false
    t.text "description", null: false
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "scope", default: "inbox", null: false
    t.bigint "inbox_id"
    t.index ["account_id", "captain_unit_id"], name: "index_captain_gallery_items_on_account_and_unit"
    t.index ["account_id", "inbox_id"], name: "index_captain_gallery_items_on_account_and_inbox"
    t.index ["account_id", "scope", "inbox_id"], name: "index_captain_gallery_items_on_account_scope_and_inbox"
    t.index ["account_id", "suite_category"], name: "index_captain_gallery_items_on_account_and_category"
    t.index ["account_id", "suite_number"], name: "index_captain_gallery_items_on_account_and_suite_number"
    t.index ["account_id"], name: "index_captain_gallery_items_on_account_id"
    t.index ["captain_unit_id"], name: "index_captain_gallery_items_on_captain_unit_id"
    t.index ["created_by_id"], name: "index_captain_gallery_items_on_created_by_id"
    t.index ["inbox_id"], name: "index_captain_gallery_items_on_inbox_id"
  end

  create_table "captain_inbox_automations", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "inbox_id", null: false
    t.string "title", null: false
    t.text "message", null: false
    t.integer "trigger_event", default: 0, null: false
    t.integer "timing", default: 1, null: false
    t.integer "offset_minutes", default: 0, null: false
    t.boolean "enabled", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "inbox_id"], name: "index_captain_inbox_automations_on_account_id_and_inbox_id"
    t.index ["account_id"], name: "index_captain_inbox_automations_on_account_id"
    t.index ["inbox_id"], name: "index_captain_inbox_automations_on_inbox_id"
  end

  create_table "captain_inbox_reminder_settings", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "inbox_id", null: false
    t.boolean "enabled", default: true, null: false
    t.text "menu_message"
    t.integer "menu_delay_minutes", default: 15, null: false
    t.text "feedback_message"
    t.integer "feedback_delay_minutes", default: 30, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "inbox_id"], name: "index_captain_inbox_reminder_settings_on_account_inbox", unique: true
    t.index ["account_id"], name: "index_captain_inbox_reminder_settings_on_account_id"
    t.index ["inbox_id"], name: "index_captain_inbox_reminder_settings_on_inbox_id"
  end

  create_table "captain_inboxes", force: :cascade do |t|
    t.bigint "captain_assistant_id", null: false
    t.bigint "inbox_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "always_use_reminder_tool", default: false, null: false
    t.bigint "captain_unit_id"
    t.index ["captain_assistant_id", "inbox_id"], name: "index_captain_inboxes_on_captain_assistant_id_and_inbox_id", unique: true
    t.index ["captain_assistant_id"], name: "index_captain_inboxes_on_captain_assistant_id"
    t.index ["captain_unit_id"], name: "index_captain_inboxes_on_captain_unit_id"
    t.index ["inbox_id"], name: "index_captain_inboxes_on_inbox_id"
  end

  create_table "captain_message_reports", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "conversation_id", null: false
    t.bigint "message_id", null: false
    t.bigint "user_id", null: false
    t.string "report_reason", null: false
    t.text "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_captain_message_reports_on_account_id"
    t.index ["conversation_id"], name: "index_captain_message_reports_on_conversation_id"
    t.index ["message_id"], name: "index_captain_message_reports_on_message_id"
    t.index ["user_id"], name: "index_captain_message_reports_on_user_id"
  end

  create_table "captain_notification_templates", force: :cascade do |t|
    t.string "label", null: false
    t.text "content", null: false
    t.integer "timing_minutes", default: 10, null: false
    t.integer "timing_direction", default: 0, null: false
    t.boolean "active", default: true, null: false
    t.integer "position", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "inbox_id", null: false
    t.index ["inbox_id", "active"], name: "idx_notif_templates_inbox_active"
  end

  create_table "captain_pix_charges", force: :cascade do |t|
    t.bigint "reservation_id", null: false
    t.bigint "unit_id", null: false
    t.string "txid"
    t.text "pix_copia_e_cola"
    t.string "status"
    t.string "e2eid"
    t.datetime "paid_at"
    t.jsonb "raw_webhook_payload"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "provider", default: "inter", null: false
    t.jsonb "manual_proof_payload"
    t.string "manual_review_reason"
    t.index ["e2eid"], name: "idx_cp_charges_e2eid"
    t.index ["e2eid"], name: "index_captain_pix_charges_on_e2eid"
    t.index ["provider"], name: "index_captain_pix_charges_on_provider"
    t.index ["reservation_id"], name: "index_captain_pix_charges_on_reservation_id"
    t.index ["txid"], name: "idx_cp_charges_txid", unique: true
    t.index ["txid"], name: "index_captain_pix_charges_on_txid"
    t.index ["unit_id"], name: "index_captain_pix_charges_on_unit_id"
  end

  create_table "captain_pricing_amounts", force: :cascade do |t|
    t.bigint "captain_pricing_category_id", null: false
    t.string "period", null: false
    t.string "day_bucket"
    t.decimal "amount", precision: 10, scale: 2, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["captain_pricing_category_id", "period", "day_bucket"], name: "idx_captain_pricing_amount_uniq", unique: true
    t.index ["captain_pricing_category_id"], name: "index_captain_pricing_amounts_on_captain_pricing_category_id"
  end

  create_table "captain_pricing_categories", force: :cascade do |t|
    t.bigint "captain_unit_id", null: false
    t.string "key", null: false
    t.jsonb "aliases", default: [], null: false
    t.integer "extra_person_starts_at", default: 3, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["captain_unit_id", "key"], name: "index_captain_pricing_categories_on_captain_unit_id_and_key", unique: true
    t.index ["captain_unit_id"], name: "index_captain_pricing_categories_on_captain_unit_id"
  end

  create_table "captain_pricing_inboxes", force: :cascade do |t|
    t.bigint "captain_pricing_id", null: false
    t.bigint "inbox_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["captain_pricing_id", "inbox_id"], name: "index_captain_pricing_inboxes_on_pricing_and_inbox", unique: true
    t.index ["inbox_id"], name: "index_captain_pricing_inboxes_on_inbox_id"
  end

  create_table "captain_pricings", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "captain_brand_id", null: false
    t.string "day_range", null: false
    t.string "suite_category", null: false
    t.string "duration", null: false
    t.decimal "price", precision: 10, scale: 2, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "inbox_id"
    t.text "keywords"
    t.index ["account_id"], name: "index_captain_pricings_on_account_id"
    t.index ["captain_brand_id"], name: "index_captain_pricings_on_captain_brand_id"
    t.index ["inbox_id"], name: "index_captain_pricings_on_inbox_id"
  end

  create_table "captain_reminders", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "inbox_id", null: false
    t.bigint "contact_id", null: false
    t.bigint "contact_inbox_id", null: false
    t.bigint "conversation_id"
    t.integer "reminder_type", default: 0, null: false
    t.integer "status", default: 0, null: false
    t.text "message"
    t.datetime "scheduled_at", null: false
    t.datetime "sent_at"
    t.integer "attempt_count", default: 0, null: false
    t.text "error_message"
    t.jsonb "metadata", default: {}, null: false
    t.string "source_type"
    t.bigint "source_id"
    t.bigint "created_by_id"
    t.string "created_by_type"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "inbox_id"], name: "index_captain_reminders_on_account_id_and_inbox_id"
    t.index ["account_id"], name: "index_captain_reminders_on_account_id"
    t.index ["contact_id", "inbox_id"], name: "index_captain_reminders_on_contact_id_and_inbox_id"
    t.index ["contact_id"], name: "index_captain_reminders_on_contact_id"
    t.index ["contact_inbox_id"], name: "index_captain_reminders_on_contact_inbox_id"
    t.index ["conversation_id"], name: "index_captain_reminders_on_conversation_id"
    t.index ["inbox_id"], name: "index_captain_reminders_on_inbox_id"
    t.index ["scheduled_at", "status"], name: "index_captain_reminders_on_scheduled_at_and_status"
    t.index ["source_type", "source_id"], name: "index_captain_reminders_on_source_type_and_source_id"
  end

  create_table "captain_reservations", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "inbox_id", null: false
    t.bigint "contact_id", null: false
    t.bigint "contact_inbox_id", null: false
    t.bigint "conversation_id"
    t.string "suite_identifier"
    t.datetime "check_in_at", null: false
    t.datetime "check_out_at", null: false
    t.integer "status", default: 0, null: false
    t.jsonb "metadata", default: {}, null: false
    t.bigint "created_by_id"
    t.string "created_by_type"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "captain_brand_id"
    t.bigint "captain_unit_id"
    t.decimal "total_amount", precision: 10, scale: 2
    t.string "payment_status", default: "pending"
    t.string "integracao_id"
    t.bigint "current_pix_charge_id"
    t.index ["account_id", "inbox_id"], name: "index_captain_reservations_on_account_id_and_inbox_id"
    t.index ["account_id", "payment_status"], name: "idx_reservations_account_payment_status"
    t.index ["account_id", "status"], name: "idx_reservations_account_status"
    t.index ["account_id"], name: "index_captain_reservations_on_account_id"
    t.index ["captain_brand_id"], name: "index_captain_reservations_on_captain_brand_id"
    t.index ["captain_unit_id", "check_in_at", "status"], name: "idx_reservations_board_unit_checkin_status"
    t.index ["captain_unit_id", "check_out_at", "status"], name: "idx_reservations_board_unit_checkout_status"
    t.index ["captain_unit_id"], name: "index_captain_reservations_on_captain_unit_id"
    t.index ["contact_id", "inbox_id"], name: "index_captain_reservations_on_contact_id_and_inbox_id"
    t.index ["contact_id"], name: "index_captain_reservations_on_contact_id"
    t.index ["contact_inbox_id"], name: "index_captain_reservations_on_contact_inbox_id"
    t.index ["conversation_id"], name: "index_captain_reservations_on_conversation_id"
    t.index ["inbox_id"], name: "index_captain_reservations_on_inbox_id"
    t.index ["integracao_id", "captain_unit_id"], name: "index_captain_reservations_on_integracao_id_and_unit_id", unique: true
    t.index ["integracao_id"], name: "index_captain_reservations_on_integracao_id"
  end

  create_table "captain_scenarios", force: :cascade do |t|
    t.string "title"
    t.text "description"
    t.text "instruction"
    t.jsonb "tools", default: []
    t.boolean "enabled", default: true, null: false
    t.bigint "assistant_id", null: false
    t.bigint "account_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "trigger_keywords"
    t.text "fallback_message"
    t.index ["account_id"], name: "index_captain_scenarios_on_account_id"
    t.index ["assistant_id", "enabled"], name: "index_captain_scenarios_on_assistant_id_and_enabled"
    t.index ["assistant_id"], name: "index_captain_scenarios_on_assistant_id"
    t.index ["enabled"], name: "index_captain_scenarios_on_enabled"
  end

  create_table "captain_tool_configs", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "inbox_id"
    t.string "tool_key"
    t.boolean "is_enabled"
    t.string "plug_play_id"
    t.string "plug_play_token"
    t.string "webhook_url"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "captain_assistant_id"
    t.text "fallback_message"
    t.index ["account_id", "inbox_id", "tool_key"], name: "index_captain_tool_configs_on_context", unique: true
    t.index ["account_id"], name: "index_captain_tool_configs_on_account_id"
    t.index ["captain_assistant_id", "tool_key"], name: "index_captain_tool_configs_on_assistant_id_and_tool_key", unique: true
    t.index ["captain_assistant_id"], name: "index_captain_tool_configs_on_captain_assistant_id"
    t.index ["inbox_id"], name: "index_captain_tool_configs_on_inbox_id"
  end

  create_table "captain_unit_inboxes", force: :cascade do |t|
    t.bigint "captain_unit_id", null: false
    t.bigint "inbox_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["captain_unit_id", "inbox_id"], name: "index_captain_unit_inboxes_on_unit_and_inbox", unique: true
    t.index ["inbox_id"], name: "index_captain_unit_inboxes_on_inbox_id"
  end

  create_table "captain_units", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "captain_brand_id", null: false
    t.string "name", null: false
    t.jsonb "visible_suite_categories", default: [], null: false
    t.jsonb "suite_category_images", default: [], null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "status"
    t.string "inter_client_id"
    t.string "inter_client_secret"
    t.string "inter_pix_key"
    t.string "inter_cert_path"
    t.string "inter_key_path"
    t.string "inter_account_number"
    t.string "webhook_url"
    t.bigint "inbox_id"
    t.string "plug_play_id"
    t.string "plug_play_token"
    t.boolean "reservations_sync_enabled"
    t.datetime "last_synced_at"
    t.string "leader_whatsapp"
    t.string "reservation_source_tag"
    t.boolean "payment_receipt_review_enabled", default: false, null: false
    t.text "inter_cert_content"
    t.text "inter_key_content"
    t.datetime "webhook_configured_at"
    t.boolean "proactive_pix_polling_enabled", default: false, null: false
    t.bigint "concierge_inbox_id"
    t.jsonb "concierge_config", default: {}, null: false
    t.uuid "supabase_unit_id"
    t.bigint "supabase_tenant_id", default: 1
    t.uuid "supabase_marca_id"
    t.decimal "extra_person_fee", precision: 10, scale: 2, default: "0.0", null: false
    t.string "currency", default: "BRL", null: false
    t.string "pix_mode", default: "inter_dynamic", null: false
    t.string "manual_pix_key"
    t.string "manual_pix_key_type"
    t.string "manual_pix_owner_name"
    t.string "manual_pix_bank_name"
    t.index ["account_id"], name: "index_captain_units_on_account_id"
    t.index ["captain_brand_id"], name: "index_captain_units_on_captain_brand_id"
    t.index ["concierge_inbox_id"], name: "index_captain_units_on_concierge_inbox_id"
    t.index ["inbox_id"], name: "index_captain_units_on_inbox_id"
    t.index ["pix_mode"], name: "index_captain_units_on_pix_mode"
    t.index ["supabase_unit_id"], name: "index_captain_units_on_supabase_unit_id", unique: true, where: "(supabase_unit_id IS NOT NULL)"
  end

  create_table "categories", force: :cascade do |t|
    t.integer "account_id", null: false
    t.integer "portal_id", null: false
    t.string "name"
    t.text "description"
    t.integer "position"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.string "locale", default: "en"
    t.string "slug", null: false
    t.bigint "parent_category_id"
    t.bigint "associated_category_id"
    t.string "icon", default: ""
    t.string "icon_color", default: ""
    t.index ["associated_category_id"], name: "index_categories_on_associated_category_id"
    t.index ["locale", "account_id"], name: "index_categories_on_locale_and_account_id"
    t.index ["locale"], name: "index_categories_on_locale"
    t.index ["parent_category_id"], name: "index_categories_on_parent_category_id"
    t.index ["slug", "locale", "portal_id"], name: "index_categories_on_slug_and_locale_and_portal_id", unique: true
  end

  create_table "channel_api", force: :cascade do |t|
    t.integer "account_id", null: false
    t.string "webhook_url"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.string "identifier"
    t.string "hmac_token"
    t.boolean "hmac_mandatory", default: false
    t.jsonb "additional_attributes", default: {}
    t.string "secret"
    t.index ["hmac_token"], name: "index_channel_api_on_hmac_token", unique: true
    t.index ["identifier"], name: "index_channel_api_on_identifier", unique: true
  end

  create_table "channel_email", force: :cascade do |t|
    t.integer "account_id", null: false
    t.string "email", null: false
    t.string "forward_to_email", null: false
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.boolean "imap_enabled", default: false
    t.string "imap_address", default: ""
    t.integer "imap_port", default: 0
    t.string "imap_login", default: ""
    t.string "imap_password", default: ""
    t.boolean "imap_enable_ssl", default: true
    t.boolean "smtp_enabled", default: false
    t.string "smtp_address", default: ""
    t.integer "smtp_port", default: 0
    t.string "smtp_login", default: ""
    t.string "smtp_password", default: ""
    t.string "smtp_domain", default: ""
    t.boolean "smtp_enable_starttls_auto", default: true
    t.string "smtp_authentication", default: "login"
    t.string "smtp_openssl_verify_mode", default: "none"
    t.boolean "smtp_enable_ssl_tls", default: false
    t.jsonb "provider_config", default: {}
    t.string "provider"
    t.boolean "verified_for_sending", default: false, null: false
    t.string "imap_authentication", default: "plain"
    t.index ["email"], name: "index_channel_email_on_email", unique: true
    t.index ["forward_to_email"], name: "index_channel_email_on_forward_to_email", unique: true
  end

  create_table "channel_facebook_pages", id: :serial, force: :cascade do |t|
    t.string "page_id", null: false
    t.string "user_access_token", null: false
    t.string "page_access_token", null: false
    t.integer "account_id", null: false
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.string "instagram_id"
    t.index ["page_id", "account_id"], name: "index_channel_facebook_pages_on_page_id_and_account_id", unique: true
    t.index ["page_id"], name: "index_channel_facebook_pages_on_page_id"
  end

  create_table "channel_instagram", force: :cascade do |t|
    t.string "access_token", null: false
    t.datetime "expires_at", null: false
    t.integer "account_id", null: false
    t.string "instagram_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["instagram_id"], name: "index_channel_instagram_on_instagram_id", unique: true
  end

  create_table "channel_line", force: :cascade do |t|
    t.integer "account_id", null: false
    t.string "line_channel_id", null: false
    t.string "line_channel_secret", null: false
    t.string "line_channel_token", null: false
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.index ["line_channel_id"], name: "index_channel_line_on_line_channel_id", unique: true
  end

  create_table "channel_sms", force: :cascade do |t|
    t.integer "account_id", null: false
    t.string "phone_number", null: false
    t.string "provider", default: "default"
    t.jsonb "provider_config", default: {}
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.index ["phone_number"], name: "index_channel_sms_on_phone_number", unique: true
  end

  create_table "channel_telegram", force: :cascade do |t|
    t.string "bot_name"
    t.integer "account_id", null: false
    t.string "bot_token", null: false
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.index ["bot_token"], name: "index_channel_telegram_on_bot_token", unique: true
  end

  create_table "channel_tiktok", force: :cascade do |t|
    t.integer "account_id", null: false
    t.string "business_id", null: false
    t.string "access_token", null: false
    t.datetime "expires_at", null: false
    t.string "refresh_token", null: false
    t.datetime "refresh_token_expires_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["business_id"], name: "index_channel_tiktok_on_business_id", unique: true
  end

  create_table "channel_twilio_sms", force: :cascade do |t|
    t.string "phone_number"
    t.string "auth_token", null: false
    t.string "account_sid", null: false
    t.integer "account_id", null: false
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.integer "medium", default: 0
    t.string "messaging_service_sid"
    t.string "api_key_sid"
    t.jsonb "content_templates", default: {}
    t.datetime "content_templates_last_updated"
    t.boolean "voice_enabled", default: false, null: false
    t.string "twiml_app_sid"
    t.string "api_key_secret"
    t.jsonb "provider_config", default: {}
    t.index ["account_sid", "phone_number"], name: "index_channel_twilio_sms_on_account_sid_and_phone_number", unique: true
    t.index ["messaging_service_sid"], name: "index_channel_twilio_sms_on_messaging_service_sid", unique: true
    t.index ["phone_number"], name: "index_channel_twilio_sms_on_phone_number", unique: true
  end

  create_table "channel_twitter_profiles", force: :cascade do |t|
    t.string "profile_id", null: false
    t.string "twitter_access_token", null: false
    t.string "twitter_access_token_secret", null: false
    t.integer "account_id", null: false
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.boolean "tweets_enabled", default: true
    t.index ["account_id", "profile_id"], name: "index_channel_twitter_profiles_on_account_id_and_profile_id", unique: true
  end

  create_table "channel_web_widgets", id: :serial, force: :cascade do |t|
    t.string "website_url"
    t.integer "account_id"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.string "website_token"
    t.string "widget_color", default: "#1f93ff"
    t.string "welcome_title"
    t.string "welcome_tagline"
    t.integer "feature_flags", default: 7, null: false
    t.integer "reply_time", default: 0
    t.string "hmac_token"
    t.boolean "pre_chat_form_enabled", default: false
    t.jsonb "pre_chat_form_options", default: {}
    t.boolean "hmac_mandatory", default: false
    t.boolean "continuity_via_email", default: true, null: false
    t.text "allowed_domains", default: ""
    t.index ["hmac_token"], name: "index_channel_web_widgets_on_hmac_token", unique: true
    t.index ["website_token"], name: "index_channel_web_widgets_on_website_token", unique: true
  end

  create_table "channel_whatsapp", force: :cascade do |t|
    t.integer "account_id", null: false
    t.string "phone_number", null: false
    t.string "provider", default: "default"
    t.jsonb "provider_config", default: {}
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.jsonb "message_templates", default: {}
    t.datetime "message_templates_last_updated", precision: nil
    t.string "wuzapi_user_token"
    t.string "wuzapi_user_token_iv"
    t.string "wuzapi_admin_token"
    t.string "wuzapi_admin_token_iv"
    t.string "evolution_api_token"
    t.string "evolution_api_token_iv"
    t.jsonb "provider_connection", default: {}
    t.string "gowa_username"
    t.string "gowa_username_iv"
    t.string "gowa_password"
    t.string "gowa_password_iv"
    t.jsonb "phone_number_health", default: {}, null: false
    t.datetime "phone_number_health_checked_at"
    t.string "phone_number_health_error", limit: 500
    t.text "business_management_token"
    t.index ["phone_number"], name: "index_channel_whatsapp_on_phone_number", unique: true
    t.index ["phone_number_health_checked_at"], name: "index_channel_whatsapp_on_phone_number_health_checked_at"
    t.index ["provider_connection"], name: "index_channel_whatsapp_provider_connection", where: "((provider)::text = ANY ((ARRAY['baileys'::character varying, 'zapi'::character varying])::text[]))", using: :gin
  end

  create_table "companies", force: :cascade do |t|
    t.string "name", null: false
    t.string "domain"
    t.text "description"
    t.bigint "account_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "contacts_count", default: 0, null: false
    t.jsonb "additional_attributes", default: {}
    t.jsonb "custom_attributes", default: {}
    t.datetime "last_activity_at", precision: nil
    t.index ["account_id", "domain"], name: "index_companies_on_account_and_domain", unique: true, where: "(domain IS NOT NULL)"
    t.index ["account_id"], name: "index_companies_on_account_id"
    t.index ["name", "account_id"], name: "index_companies_on_name_and_account_id"
  end

  create_table "contact_inboxes", force: :cascade do |t|
    t.bigint "contact_id"
    t.bigint "inbox_id"
    t.text "source_id", null: false
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.boolean "hmac_verified", default: false
    t.string "pubsub_token"
    t.index ["contact_id"], name: "index_contact_inboxes_on_contact_id"
    t.index ["inbox_id", "source_id"], name: "index_contact_inboxes_on_inbox_id_and_source_id", unique: true
    t.index ["inbox_id"], name: "index_contact_inboxes_on_inbox_id"
    t.index ["pubsub_token"], name: "index_contact_inboxes_on_pubsub_token", unique: true
    t.index ["source_id"], name: "index_contact_inboxes_on_source_id"
  end

  create_table "contacts", id: :serial, force: :cascade do |t|
    t.string "name", default: ""
    t.string "email"
    t.string "phone_number"
    t.integer "account_id", null: false
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.jsonb "additional_attributes", default: {}
    t.string "identifier"
    t.jsonb "custom_attributes", default: {}
    t.datetime "last_activity_at", precision: nil
    t.integer "contact_type", default: 0
    t.string "middle_name", default: ""
    t.string "last_name", default: ""
    t.string "location", default: ""
    t.string "country_code", default: ""
    t.boolean "blocked", default: false, null: false
    t.bigint "company_id"
    t.integer "interactions_count", default: 0, null: false
    t.integer "one_shot_consultations_count", default: 0, null: false
    t.datetime "first_interaction_at"
    t.datetime "last_interaction_at"
    t.integer "pix_generated_count", default: 0, null: false
    t.integer "reservations_paid_count", default: 0, null: false
    t.boolean "is_recurring", default: false, null: false
    t.integer "days_since_last_interaction"
    t.integer "group_type", default: 0, null: false
    t.index "lower((email)::text), account_id", name: "index_contacts_on_lower_email_account_id"
    t.index ["account_id", "contact_type"], name: "index_contacts_on_account_id_and_contact_type"
    t.index ["account_id", "email", "phone_number", "identifier"], name: "index_contacts_on_nonempty_fields", where: "(((email)::text <> ''::text) OR ((phone_number)::text <> ''::text) OR ((identifier)::text <> ''::text))"
    t.index ["account_id", "group_type"], name: "index_contacts_on_account_id_and_group_type"
    t.index ["account_id", "is_recurring", "last_interaction_at"], name: "idx_contacts_account_recurring_last"
    t.index ["account_id", "last_activity_at"], name: "index_contacts_on_account_id_and_last_activity_at", order: { last_activity_at: "DESC NULLS LAST" }
    t.index ["account_id"], name: "index_contacts_on_account_id"
    t.index ["account_id"], name: "index_resolved_contact_account_id", where: "(((email)::text <> ''::text) OR ((phone_number)::text <> ''::text) OR ((identifier)::text <> ''::text))"
    t.index ["blocked"], name: "index_contacts_on_blocked"
    t.index ["company_id"], name: "index_contacts_on_company_id"
    t.index ["days_since_last_interaction"], name: "index_contacts_on_days_since_last_interaction"
    t.index ["email", "account_id"], name: "uniq_email_per_account_contact", unique: true
    t.index ["identifier", "account_id"], name: "uniq_identifier_per_account_contact", unique: true
    t.index ["is_recurring"], name: "index_contacts_on_is_recurring"
    t.index ["last_interaction_at"], name: "index_contacts_on_last_interaction_at"
    t.index ["name", "email", "phone_number", "identifier"], name: "index_contacts_on_name_email_phone_number_identifier", opclass: :gin_trgm_ops, using: :gin
    t.index ["phone_number", "account_id"], name: "index_contacts_on_phone_number_and_account_id"
  end

  create_table "conversation_outcomes", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "assistant_id", null: false
    t.bigint "conversation_id", null: false
    t.bigint "inbox_id", null: false
    t.datetime "first_captain_reply_at"
    t.datetime "last_captain_reply_at"
    t.integer "captain_reply_count", default: 0, null: false
    t.datetime "first_human_reply_at"
    t.datetime "handoff_at"
    t.string "handoff_reason_category"
    t.datetime "resolved_at"
    t.integer "csat_rating"
    t.datetime "csat_received_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "episode_trigger", default: "initial", null: false
    t.datetime "started_at", null: false
    t.datetime "ended_at"
    t.index ["account_id", "assistant_id", "handoff_at"], name: "idx_conversation_outcomes_on_assistant_handoff_at"
    t.index ["account_id", "assistant_id", "resolved_at"], name: "idx_conversation_outcomes_on_assistant_resolved_at"
    t.index ["account_id", "assistant_id", "started_at"], name: "idx_conversation_outcomes_on_assistant_started_at"
    t.index ["account_id", "conversation_id", "started_at"], name: "idx_conversation_outcomes_unique_boundary", unique: true
    t.index ["account_id", "conversation_id"], name: "idx_conversation_outcomes_initial_episode", unique: true, where: "((episode_trigger)::text = 'initial'::text)"
    t.index ["account_id", "conversation_id"], name: "idx_conversation_outcomes_open_episode", unique: true, where: "(ended_at IS NULL)"
    t.index ["account_id"], name: "index_conversation_outcomes_on_account_id"
    t.index ["assistant_id"], name: "index_conversation_outcomes_on_assistant_id"
    t.index ["conversation_id"], name: "index_conversation_outcomes_on_conversation_id"
    t.index ["inbox_id"], name: "index_conversation_outcomes_on_inbox_id"
  end

  create_table "conversation_participants", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "user_id", null: false
    t.bigint "conversation_id", null: false
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.index ["account_id"], name: "index_conversation_participants_on_account_id"
    t.index ["conversation_id"], name: "index_conversation_participants_on_conversation_id"
    t.index ["user_id", "conversation_id"], name: "index_conversation_participants_on_user_id_and_conversation_id", unique: true
    t.index ["user_id"], name: "index_conversation_participants_on_user_id"
  end

  create_table "conversation_pins", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "user_id", null: false
    t.bigint "conversation_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_conversation_pins_on_account_id"
    t.index ["conversation_id"], name: "index_conversation_pins_on_conversation_id"
    t.index ["user_id", "conversation_id"], name: "index_conversation_pins_on_user_id_and_conversation_id", unique: true
  end

  create_table "conversations", id: :serial, force: :cascade do |t|
    t.integer "account_id", null: false
    t.integer "inbox_id", null: false
    t.integer "status", default: 0, null: false
    t.integer "assignee_id"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.bigint "contact_id", null: false
    t.integer "display_id", null: false
    t.datetime "contact_last_seen_at", precision: nil
    t.datetime "agent_last_seen_at", precision: nil
    t.jsonb "additional_attributes", default: {}
    t.bigint "contact_inbox_id"
    t.uuid "uuid", default: -> { "gen_random_uuid()" }, null: false
    t.string "identifier"
    t.datetime "last_activity_at", precision: nil, default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.bigint "team_id"
    t.bigint "campaign_id"
    t.datetime "snoozed_until", precision: nil
    t.jsonb "custom_attributes", default: {}
    t.datetime "assignee_last_seen_at", precision: nil
    t.datetime "first_reply_created_at", precision: nil
    t.integer "priority"
    t.bigint "sla_policy_id"
    t.datetime "waiting_since"
    t.text "cached_label_list"
    t.bigint "assignee_agent_bot_id"
    t.string "active_scenario_key"
    t.datetime "active_scenario_expires_at"
    t.jsonb "active_scenario_state", default: {}, null: false
    t.integer "group_type", default: 0, null: false
    t.datetime "status_changed_at"
    t.index ["account_id", "display_id"], name: "index_conversations_on_account_id_and_display_id", unique: true
    t.index ["account_id", "group_type"], name: "index_conversations_on_account_id_and_group_type"
    t.index ["account_id", "id"], name: "index_conversations_on_id_and_account_id"
    t.index ["account_id", "inbox_id", "status", "assignee_id"], name: "conv_acid_inbid_stat_asgnid_idx"
    t.index ["account_id", "status", "created_at"], name: "index_conversations_on_account_id_status_created_at"
    t.index ["account_id"], name: "index_conversations_on_account_id"
    t.index ["active_scenario_key"], name: "index_conversations_on_active_scenario_key"
    t.index ["assignee_id", "account_id"], name: "index_conversations_on_assignee_id_and_account_id"
    t.index ["campaign_id"], name: "index_conversations_on_campaign_id"
    t.index ["contact_id"], name: "index_conversations_on_contact_id"
    t.index ["contact_inbox_id"], name: "index_conversations_on_contact_inbox_id"
    t.index ["created_at"], name: "index_conversations_on_created_at"
    t.index ["first_reply_created_at"], name: "index_conversations_on_first_reply_created_at"
    t.index ["identifier", "account_id"], name: "index_conversations_on_identifier_and_account_id"
    t.index ["inbox_id", "group_type"], name: "index_conversations_on_inbox_id_and_group_type"
    t.index ["inbox_id"], name: "index_conversations_on_inbox_id"
    t.index ["priority"], name: "index_conversations_on_priority"
    t.index ["status", "account_id"], name: "index_conversations_on_status_and_account_id"
    t.index ["status", "priority"], name: "index_conversations_on_status_and_priority"
    t.index ["team_id"], name: "index_conversations_on_team_id"
    t.index ["uuid"], name: "index_conversations_on_uuid", unique: true
    t.index ["waiting_since"], name: "index_conversations_on_waiting_since"
  end

  create_table "copilot_messages", force: :cascade do |t|
    t.bigint "copilot_thread_id", null: false
    t.bigint "account_id", null: false
    t.jsonb "message", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "message_type", default: 0
    t.index ["account_id"], name: "index_copilot_messages_on_account_id"
    t.index ["copilot_thread_id"], name: "index_copilot_messages_on_copilot_thread_id"
  end

  create_table "copilot_threads", force: :cascade do |t|
    t.string "title", null: false
    t.bigint "user_id", null: false
    t.bigint "account_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "assistant_id"
    t.index ["account_id"], name: "index_copilot_threads_on_account_id"
    t.index ["assistant_id"], name: "index_copilot_threads_on_assistant_id"
    t.index ["user_id"], name: "index_copilot_threads_on_user_id"
  end

  create_table "csat_survey_responses", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "conversation_id", null: false
    t.bigint "message_id", null: false
    t.integer "rating", null: false
    t.text "feedback_message"
    t.bigint "contact_id", null: false
    t.bigint "assigned_agent_id"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.text "csat_review_notes"
    t.datetime "review_notes_updated_at"
    t.bigint "review_notes_updated_by_id"
    t.index ["account_id"], name: "index_csat_survey_responses_on_account_id"
    t.index ["assigned_agent_id"], name: "index_csat_survey_responses_on_assigned_agent_id"
    t.index ["contact_id"], name: "index_csat_survey_responses_on_contact_id"
    t.index ["conversation_id"], name: "index_csat_survey_responses_on_conversation_id"
    t.index ["message_id"], name: "index_csat_survey_responses_on_message_id", unique: true
    t.index ["review_notes_updated_by_id"], name: "index_csat_survey_responses_on_review_notes_updated_by_id"
  end

  create_table "custom_attribute_definitions", force: :cascade do |t|
    t.string "attribute_display_name"
    t.string "attribute_key"
    t.integer "attribute_display_type", default: 0
    t.integer "default_value"
    t.integer "attribute_model", default: 0
    t.bigint "account_id"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.text "attribute_description"
    t.jsonb "attribute_values", default: []
    t.string "regex_pattern"
    t.string "regex_cue"
    t.index ["account_id"], name: "index_custom_attribute_definitions_on_account_id"
    t.index ["attribute_key", "attribute_model", "account_id"], name: "attribute_key_model_index", unique: true
  end

  create_table "custom_filters", force: :cascade do |t|
    t.string "name", null: false
    t.integer "filter_type", default: 0, null: false
    t.jsonb "query", default: "{}", null: false
    t.bigint "account_id", null: false
    t.bigint "user_id", null: false
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.integer "visibility", default: 0, null: false
    t.index ["account_id", "filter_type", "visibility", "user_id"], name: "index_custom_filters_on_account_type_visibility_user"
    t.index ["account_id"], name: "index_custom_filters_on_account_id"
    t.index ["user_id"], name: "index_custom_filters_on_user_id"
  end

  create_table "custom_roles", force: :cascade do |t|
    t.string "name"
    t.string "description"
    t.bigint "account_id", null: false
    t.text "permissions", default: [], array: true
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_custom_roles_on_account_id"
  end

  create_table "dashboard_apps", force: :cascade do |t|
    t.string "title", null: false
    t.jsonb "content", default: []
    t.bigint "account_id", null: false
    t.bigint "user_id"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.boolean "show_on_sidebar", default: false, null: false
    t.index ["account_id"], name: "index_dashboard_apps_on_account_id"
    t.index ["user_id"], name: "index_dashboard_apps_on_user_id"
  end

  create_table "data_import_errors", force: :cascade do |t|
    t.bigint "data_import_id", null: false
    t.bigint "data_import_item_id"
    t.string "source_object_type"
    t.string "source_object_id"
    t.string "error_code", null: false
    t.text "message"
    t.jsonb "details", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["data_import_id"], name: "index_data_import_errors_on_data_import_id"
    t.index ["data_import_item_id"], name: "index_data_import_errors_on_data_import_item_id"
    t.index ["source_object_type", "source_object_id"], name: "idx_data_import_errors_on_source"
  end

  create_table "data_import_items", force: :cascade do |t|
    t.bigint "data_import_id", null: false
    t.string "source_provider", null: false
    t.string "source_object_type", null: false
    t.string "source_object_id", null: false
    t.integer "status", default: 0, null: false
    t.string "chatwoot_record_type"
    t.bigint "chatwoot_record_id"
    t.integer "attempt_count", default: 0, null: false
    t.string "last_error_code"
    t.text "last_error_message"
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["chatwoot_record_type", "chatwoot_record_id"], name: "idx_data_import_items_on_record"
    t.index ["data_import_id", "source_object_type", "source_object_id"], name: "idx_data_import_items_on_import_and_source", unique: true
    t.index ["data_import_id"], name: "index_data_import_items_on_data_import_id"
    t.index ["source_provider", "source_object_type", "source_object_id"], name: "idx_data_import_items_on_source"
  end

  create_table "data_import_mappings", force: :cascade do |t|
    t.integer "account_id", null: false
    t.bigint "data_import_id", null: false
    t.string "source_provider", null: false
    t.string "source_object_type", null: false
    t.string "source_object_id", null: false
    t.string "chatwoot_record_type", null: false
    t.bigint "chatwoot_record_id", null: false
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "source_provider", "source_object_type", "source_object_id"], name: "idx_data_import_mappings_on_account_and_source", unique: true
    t.index ["chatwoot_record_type", "chatwoot_record_id"], name: "idx_data_import_mappings_on_record"
    t.index ["data_import_id"], name: "index_data_import_mappings_on_data_import_id"
  end

  create_table "data_imports", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "data_type", null: false
    t.integer "status", default: 0, null: false
    t.text "processing_errors"
    t.integer "total_records"
    t.integer "processed_records"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.string "name"
    t.string "source_type"
    t.string "source_provider"
    t.jsonb "import_types", default: [], null: false
    t.integer "initiated_by_id"
    t.text "access_token"
    t.jsonb "source_metadata", default: {}, null: false
    t.jsonb "stats", default: {}, null: false
    t.jsonb "cursor", default: {}, null: false
    t.datetime "started_at"
    t.datetime "completed_at"
    t.datetime "abandoned_at"
    t.datetime "last_error_at"
    t.index ["account_id"], name: "index_data_imports_on_account_id"
    t.index ["initiated_by_id"], name: "index_data_imports_on_initiated_by_id"
    t.index ["source_provider"], name: "index_data_imports_on_source_provider"
  end

  create_table "email_templates", force: :cascade do |t|
    t.string "name", null: false
    t.text "body", null: false
    t.integer "account_id"
    t.integer "template_type", default: 1
    t.integer "locale", default: 0, null: false
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.integer "inbox_id"
    t.index ["account_id", "name", "template_type", "locale"], name: "index_email_templates_on_account_scope", unique: true, where: "((account_id IS NOT NULL) AND (inbox_id IS NULL))"
    t.index ["inbox_id", "name", "template_type", "locale"], name: "index_email_templates_on_inbox_scope", unique: true, where: "(inbox_id IS NOT NULL)"
    t.index ["inbox_id"], name: "index_email_templates_on_inbox_id"
    t.index ["name", "template_type", "locale"], name: "index_email_templates_on_installation_scope", unique: true, where: "((account_id IS NULL) AND (inbox_id IS NULL))"
  end

  create_table "folders", force: :cascade do |t|
    t.integer "account_id", null: false
    t.integer "category_id", null: false
    t.string "name"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
  end

  create_table "group_members", force: :cascade do |t|
    t.bigint "group_contact_id", null: false
    t.bigint "contact_id", null: false
    t.integer "role", default: 0, null: false
    t.boolean "is_active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["contact_id"], name: "index_group_members_on_contact_id"
    t.index ["group_contact_id", "contact_id"], name: "index_group_members_on_group_contact_id_and_contact_id", unique: true
    t.index ["group_contact_id", "is_active"], name: "index_group_members_on_group_contact_id_and_is_active"
    t.index ["group_contact_id"], name: "index_group_members_on_group_contact_id"
  end

  create_table "inbox_assignment_policies", force: :cascade do |t|
    t.bigint "inbox_id", null: false
    t.bigint "assignment_policy_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["assignment_policy_id"], name: "index_inbox_assignment_policies_on_assignment_policy_id"
    t.index ["inbox_id"], name: "index_inbox_assignment_policies_on_inbox_id", unique: true
  end

  create_table "inbox_capacity_limits", force: :cascade do |t|
    t.bigint "agent_capacity_policy_id", null: false
    t.bigint "inbox_id", null: false
    t.integer "conversation_limit", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["agent_capacity_policy_id", "inbox_id"], name: "idx_on_agent_capacity_policy_id_inbox_id_71c7ec4caf", unique: true
    t.index ["agent_capacity_policy_id"], name: "index_inbox_capacity_limits_on_agent_capacity_policy_id"
    t.index ["inbox_id"], name: "index_inbox_capacity_limits_on_inbox_id"
  end

  create_table "inbox_members", id: :serial, force: :cascade do |t|
    t.integer "user_id", null: false
    t.integer "inbox_id", null: false
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.index ["inbox_id", "user_id"], name: "index_inbox_members_on_inbox_id_and_user_id", unique: true
    t.index ["inbox_id"], name: "index_inbox_members_on_inbox_id"
  end

  create_table "inbox_signatures", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "inbox_id", null: false
    t.text "message_signature", null: false
    t.string "signature_position", default: "top", null: false
    t.string "signature_separator", default: "blank", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["inbox_id"], name: "index_inbox_signatures_on_inbox_id"
    t.index ["user_id", "inbox_id"], name: "index_inbox_signatures_on_user_id_and_inbox_id", unique: true
  end

  create_table "inboxes", id: :serial, force: :cascade do |t|
    t.integer "channel_id", null: false
    t.integer "account_id", null: false
    t.string "name", null: false
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.string "channel_type"
    t.boolean "enable_auto_assignment", default: true
    t.boolean "greeting_enabled", default: false
    t.string "greeting_message"
    t.string "email_address"
    t.boolean "working_hours_enabled", default: false
    t.string "out_of_office_message"
    t.string "timezone", default: "UTC"
    t.boolean "enable_email_collect", default: true
    t.boolean "csat_survey_enabled", default: false
    t.boolean "allow_messages_after_resolved", default: true
    t.jsonb "auto_assignment_config", default: {}
    t.boolean "lock_to_single_conversation", default: false, null: false
    t.bigint "portal_id"
    t.integer "sender_name_type", default: 0, null: false
    t.string "business_name"
    t.jsonb "csat_config", default: {}, null: false
    t.integer "auto_resolve_duration"
    t.boolean "message_signature_enabled"
    t.integer "typing_delay", default: 0
    t.string "message_signature_default_name"
    t.string "message_signature_day_name"
    t.string "message_signature_night_even_name"
    t.string "message_signature_night_odd_name"
    t.string "message_signature_night_shift_start", default: "19:00"
    t.string "message_signature_night_shift_end", default: "07:00"
    t.boolean "prevent_assignment_takeover", default: false, null: false
    t.index ["account_id"], name: "index_inboxes_on_account_id"
    t.index ["channel_id", "channel_type"], name: "index_inboxes_on_channel_id_and_channel_type"
    t.index ["portal_id"], name: "index_inboxes_on_portal_id"
  end

  create_table "installation_configs", force: :cascade do |t|
    t.string "name", null: false
    t.jsonb "serialized_value", default: {}, null: false
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.boolean "locked", default: true, null: false
    t.index ["name", "created_at"], name: "index_installation_configs_on_name_and_created_at", unique: true
    t.index ["name"], name: "index_installation_configs_on_name", unique: true
  end

  create_table "integrations_hooks", force: :cascade do |t|
    t.integer "status", default: 1
    t.integer "inbox_id"
    t.integer "account_id"
    t.string "app_id"
    t.integer "hook_type", default: 0
    t.string "reference_id"
    t.string "access_token"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.jsonb "settings", default: {}
  end

  create_table "internal_chat_categories", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "name", null: false
    t.integer "position", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "name"], name: "index_internal_chat_categories_on_account_id_and_name", unique: true
    t.index ["account_id", "position"], name: "index_internal_chat_categories_on_account_id_and_position"
    t.index ["account_id"], name: "index_internal_chat_categories_on_account_id"
  end

  create_table "internal_chat_channel_members", force: :cascade do |t|
    t.bigint "internal_chat_channel_id", null: false
    t.bigint "user_id", null: false
    t.integer "role", default: 0, null: false
    t.boolean "muted", default: false, null: false
    t.datetime "last_read_at"
    t.boolean "favorited", default: false, null: false
    t.boolean "hidden", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["internal_chat_channel_id", "user_id"], name: "idx_ic_channel_members_channel_user", unique: true
    t.index ["user_id", "favorited"], name: "idx_ic_channel_members_user_favorited"
    t.index ["user_id"], name: "index_internal_chat_channel_members_on_user_id"
  end

  create_table "internal_chat_channel_teams", force: :cascade do |t|
    t.bigint "internal_chat_channel_id", null: false
    t.bigint "team_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["internal_chat_channel_id", "team_id"], name: "idx_ic_channel_teams_channel_team", unique: true
    t.index ["team_id"], name: "index_internal_chat_channel_teams_on_team_id"
  end

  create_table "internal_chat_channels", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "category_id"
    t.string "name"
    t.text "description"
    t.integer "channel_type", default: 0, null: false
    t.integer "status", default: 0, null: false
    t.bigint "created_by_id"
    t.datetime "last_activity_at", null: false
    t.integer "messages_count", default: 0
    t.uuid "uuid", default: -> { "gen_random_uuid()" }, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index "f_unaccent((name)::text) gin_trgm_ops", name: "idx_ic_channels_name_unaccent_trgm", using: :gin
    t.index "f_unaccent(description) gin_trgm_ops", name: "idx_ic_channels_description_unaccent_trgm", using: :gin
    t.index ["account_id", "category_id"], name: "index_internal_chat_channels_on_account_id_and_category_id"
    t.index ["account_id", "channel_type"], name: "index_internal_chat_channels_on_account_id_and_channel_type"
    t.index ["account_id", "status"], name: "index_internal_chat_channels_on_account_id_and_status"
    t.index ["account_id"], name: "index_internal_chat_channels_on_account_id"
    t.index ["category_id"], name: "index_internal_chat_channels_on_category_id"
    t.index ["uuid"], name: "index_internal_chat_channels_on_uuid", unique: true
  end

  create_table "internal_chat_drafts", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "user_id", null: false
    t.bigint "internal_chat_channel_id", null: false
    t.text "content", null: false
    t.bigint "parent_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_internal_chat_drafts_on_account_id"
    t.index ["internal_chat_channel_id"], name: "idx_ic_drafts_channel"
    t.index ["user_id", "internal_chat_channel_id", "parent_id"], name: "idx_ic_drafts_user_channel_thread", unique: true, where: "(parent_id IS NOT NULL)"
    t.index ["user_id", "internal_chat_channel_id"], name: "idx_ic_drafts_user_channel_root", unique: true, where: "(parent_id IS NULL)"
    t.index ["user_id", "updated_at"], name: "idx_ic_drafts_user_updated"
    t.index ["user_id"], name: "index_internal_chat_drafts_on_user_id"
  end

  create_table "internal_chat_message_attachments", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "internal_chat_message_id", null: false
    t.integer "file_type", default: 0, null: false
    t.string "external_url"
    t.string "extension"
    t.jsonb "meta", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_internal_chat_message_attachments_on_account_id"
    t.index ["internal_chat_message_id"], name: "idx_ic_msg_attachments_message"
  end

  create_table "internal_chat_messages", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "internal_chat_channel_id", null: false
    t.bigint "sender_id"
    t.text "content"
    t.integer "content_type", default: 0, null: false
    t.bigint "parent_id"
    t.integer "replies_count", default: 0, null: false
    t.jsonb "content_attributes", default: {}
    t.string "echo_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index "f_unaccent(content) gin_trgm_ops", name: "idx_ic_messages_content_unaccent_trgm", using: :gin
    t.index ["account_id", "created_at"], name: "idx_ic_messages_account_created"
    t.index ["account_id"], name: "index_internal_chat_messages_on_account_id"
    t.index ["internal_chat_channel_id", "created_at"], name: "idx_ic_messages_channel_created"
    t.index ["internal_chat_channel_id"], name: "index_internal_chat_messages_on_internal_chat_channel_id"
    t.index ["parent_id"], name: "index_internal_chat_messages_on_parent_id"
    t.index ["sender_id"], name: "index_internal_chat_messages_on_sender_id"
  end

  create_table "internal_chat_poll_options", force: :cascade do |t|
    t.bigint "internal_chat_poll_id", null: false
    t.string "text", null: false
    t.string "emoji"
    t.string "image_url"
    t.integer "position", default: 0, null: false
    t.integer "votes_count", default: 0, null: false
    t.datetime "created_at", null: false
    t.index ["internal_chat_poll_id", "position"], name: "idx_ic_poll_options_poll_pos"
    t.index ["internal_chat_poll_id"], name: "idx_ic_poll_options_poll"
  end

  create_table "internal_chat_poll_votes", force: :cascade do |t|
    t.bigint "internal_chat_poll_option_id", null: false
    t.bigint "user_id", null: false
    t.datetime "created_at", null: false
    t.index ["internal_chat_poll_option_id", "user_id"], name: "idx_ic_poll_votes_option_user", unique: true
    t.index ["internal_chat_poll_option_id"], name: "idx_ic_poll_votes_option"
    t.index ["user_id"], name: "index_internal_chat_poll_votes_on_user_id"
  end

  create_table "internal_chat_polls", force: :cascade do |t|
    t.bigint "internal_chat_message_id", null: false
    t.string "question", null: false
    t.boolean "multiple_choice", default: false, null: false
    t.boolean "public_results", default: true, null: false
    t.boolean "allow_revote", default: true, null: false
    t.datetime "expires_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["internal_chat_message_id"], name: "idx_ic_polls_message"
    t.index ["internal_chat_message_id"], name: "idx_ic_polls_message_unique", unique: true
  end

  create_table "internal_chat_reactions", force: :cascade do |t|
    t.bigint "internal_chat_message_id", null: false
    t.bigint "user_id", null: false
    t.string "emoji", null: false
    t.datetime "created_at", null: false
    t.index ["internal_chat_message_id", "user_id", "emoji"], name: "idx_ic_reactions_message_user_emoji", unique: true
    t.index ["internal_chat_message_id"], name: "idx_ic_reactions_message"
    t.index ["user_id"], name: "index_internal_chat_reactions_on_user_id"
  end

  create_table "labels", force: :cascade do |t|
    t.string "title"
    t.text "description"
    t.string "color", default: "#1f93ff", null: false
    t.boolean "show_on_sidebar"
    t.bigint "account_id"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.index ["account_id"], name: "index_labels_on_account_id"
    t.index ["title", "account_id"], name: "index_labels_on_title_and_account_id", unique: true
  end

  create_table "landing_hosts", force: :cascade do |t|
    t.string "hostname"
    t.string "unit_code"
    t.integer "inbox_id"
    t.boolean "active"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "auto_label"
    t.string "page_title", default: "Atendimento Express"
    t.string "page_subtitle", default: "Atendimento Imediato\nEntrada Discreta\nSem Burocracia"
    t.string "button_text", default: "Ver disponibilidade agora"
    t.string "logo_url"
    t.string "suite_image_url"
    t.string "theme_color", default: "#25D366"
    t.string "whatsapp_number", default: ""
    t.text "initial_message"
    t.string "default_source"
    t.string "default_campanha"
    t.jsonb "custom_config", default: {}
    t.index ["hostname"], name: "index_landing_hosts_on_hostname", unique: true
  end

  create_table "lead_clicks", force: :cascade do |t|
    t.integer "inbox_id"
    t.string "ip"
    t.string "user_agent"
    t.string "hostname"
    t.string "source"
    t.string "campanha"
    t.string "lp"
    t.integer "status"
    t.integer "conversation_id"
    t.integer "contact_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "click_id"
    t.index ["inbox_id", "ip", "status", "created_at"], name: "index_lead_clicks_on_inbox_id_and_ip_and_status_and_created_at"
  end

  create_table "leaves", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "user_id", null: false
    t.date "start_date", null: false
    t.date "end_date", null: false
    t.integer "leave_type", default: 0, null: false
    t.integer "status", default: 0, null: false
    t.text "reason"
    t.bigint "approved_by_id"
    t.datetime "approved_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "status"], name: "index_leaves_on_account_id_and_status"
    t.index ["account_id"], name: "index_leaves_on_account_id"
    t.index ["approved_by_id"], name: "index_leaves_on_approved_by_id"
    t.index ["user_id"], name: "index_leaves_on_user_id"
  end

  create_table "macros", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "name", null: false
    t.integer "visibility", default: 0
    t.bigint "created_by_id"
    t.bigint "updated_by_id"
    t.jsonb "actions", default: {}, null: false
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.index ["account_id"], name: "index_macros_on_account_id"
  end

  create_table "mentions", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "conversation_id", null: false
    t.bigint "account_id", null: false
    t.datetime "mentioned_at", precision: nil, null: false
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.index ["account_id"], name: "index_mentions_on_account_id"
    t.index ["conversation_id"], name: "index_mentions_on_conversation_id"
    t.index ["user_id", "conversation_id"], name: "index_mentions_on_user_id_and_conversation_id", unique: true
    t.index ["user_id"], name: "index_mentions_on_user_id"
  end

  create_table "messages", id: :serial, force: :cascade do |t|
    t.text "content"
    t.integer "account_id", null: false
    t.integer "inbox_id", null: false
    t.integer "conversation_id", null: false
    t.integer "message_type", null: false
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.boolean "private", default: false, null: false
    t.integer "status", default: 0
    t.text "source_id"
    t.integer "content_type", default: 0, null: false
    t.json "content_attributes", default: {}
    t.string "sender_type"
    t.bigint "sender_id"
    t.jsonb "external_source_ids", default: {}
    t.jsonb "additional_attributes", default: {}
    t.text "processed_message_content"
    t.jsonb "sentiment", default: {}
    t.integer "in_reply_to_id"
    t.index "((additional_attributes -> 'campaign_id'::text))", name: "index_messages_on_additional_attributes_campaign_id", using: :gin
    t.index ["account_id", "content_type", "created_at"], name: "idx_messages_account_content_created"
    t.index ["account_id", "created_at", "message_type"], name: "index_messages_on_account_created_type"
    t.index ["account_id", "inbox_id"], name: "index_messages_on_account_id_and_inbox_id"
    t.index ["account_id"], name: "index_messages_on_account_id"
    t.index ["content"], name: "index_messages_on_content", opclass: :gin_trgm_ops, using: :gin
    t.index ["conversation_id", "account_id", "message_type", "created_at"], name: "index_messages_on_conversation_account_type_created"
    t.index ["conversation_id"], name: "index_messages_on_conversation_id"
    t.index ["created_at"], name: "index_messages_on_created_at"
    t.index ["in_reply_to_id"], name: "index_messages_on_in_reply_to_id"
    t.index ["inbox_id"], name: "index_messages_on_inbox_id"
    t.index ["sender_type", "sender_id", "created_at"], name: "index_messages_on_sender_and_created"
    t.index ["sender_type", "sender_id"], name: "index_messages_on_sender_type_and_sender_id"
    t.index ["source_id"], name: "index_messages_on_source_id"
  end

  create_table "notes", force: :cascade do |t|
    t.text "content", null: false
    t.bigint "account_id", null: false
    t.bigint "contact_id", null: false
    t.bigint "user_id"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.index ["account_id"], name: "index_notes_on_account_id"
    t.index ["contact_id"], name: "index_notes_on_contact_id"
    t.index ["user_id"], name: "index_notes_on_user_id"
  end

  create_table "notification_settings", force: :cascade do |t|
    t.integer "account_id"
    t.integer "user_id"
    t.integer "email_flags", default: 0, null: false
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.integer "push_flags", default: 0, null: false
    t.index ["account_id", "user_id"], name: "by_account_user", unique: true
  end

  create_table "notification_subscriptions", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.integer "subscription_type", null: false
    t.jsonb "subscription_attributes", default: {}, null: false
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.text "identifier"
    t.index ["identifier"], name: "index_notification_subscriptions_on_identifier", unique: true
    t.index ["user_id"], name: "index_notification_subscriptions_on_user_id"
  end

  create_table "notifications", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "user_id", null: false
    t.integer "notification_type", null: false
    t.string "primary_actor_type", null: false
    t.bigint "primary_actor_id", null: false
    t.string "secondary_actor_type"
    t.bigint "secondary_actor_id"
    t.datetime "read_at", precision: nil
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.datetime "snoozed_until"
    t.datetime "last_activity_at", default: -> { "CURRENT_TIMESTAMP" }
    t.jsonb "meta", default: {}
    t.index ["account_id"], name: "index_notifications_on_account_id"
    t.index ["last_activity_at"], name: "index_notifications_on_last_activity_at"
    t.index ["primary_actor_type", "primary_actor_id"], name: "uniq_primary_actor_per_account_notifications"
    t.index ["secondary_actor_type", "secondary_actor_id"], name: "uniq_secondary_actor_per_account_notifications"
    t.index ["user_id", "account_id", "snoozed_until", "read_at"], name: "idx_notifications_performance"
    t.index ["user_id"], name: "index_notifications_on_user_id"
  end

  create_table "platform_app_permissibles", force: :cascade do |t|
    t.bigint "platform_app_id", null: false
    t.string "permissible_type", null: false
    t.bigint "permissible_id", null: false
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.index ["permissible_type", "permissible_id"], name: "index_platform_app_permissibles_on_permissibles"
    t.index ["platform_app_id", "permissible_id", "permissible_type"], name: "unique_permissibles_index", unique: true
    t.index ["platform_app_id"], name: "index_platform_app_permissibles_on_platform_app_id"
  end

  create_table "platform_apps", force: :cascade do |t|
    t.string "name", null: false
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
  end

  create_table "platform_banners", force: :cascade do |t|
    t.text "banner_message", null: false
    t.integer "banner_type", default: 0, null: false
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "portals", force: :cascade do |t|
    t.integer "account_id", null: false
    t.string "name", null: false
    t.string "slug", null: false
    t.string "custom_domain"
    t.string "color"
    t.string "homepage_link"
    t.string "page_title"
    t.text "header_text"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.jsonb "config", default: {"allowed_locales" => ["en"]}
    t.boolean "archived", default: false
    t.bigint "channel_web_widget_id"
    t.jsonb "ssl_settings", default: {}, null: false
    t.text "custom_head_html"
    t.text "custom_body_html"
    t.index ["channel_web_widget_id"], name: "index_portals_on_channel_web_widget_id"
    t.index ["custom_domain"], name: "index_portals_on_custom_domain", unique: true
    t.index ["slug"], name: "index_portals_on_slug", unique: true
  end

  create_table "portals_members", id: false, force: :cascade do |t|
    t.bigint "portal_id", null: false
    t.bigint "user_id", null: false
    t.index ["portal_id", "user_id"], name: "index_portals_members_on_portal_id_and_user_id", unique: true
    t.index ["portal_id"], name: "index_portals_members_on_portal_id"
    t.index ["user_id"], name: "index_portals_members_on_user_id"
  end

  create_table "recurring_scheduled_messages", force: :cascade do |t|
    t.text "content"
    t.jsonb "template_params", default: {}
    t.jsonb "recurrence_rule", default: {}, null: false
    t.integer "status", default: 0, null: false
    t.integer "occurrences_sent", default: 0, null: false
    t.bigint "account_id", null: false
    t.bigint "conversation_id", null: false
    t.bigint "inbox_id", null: false
    t.string "author_type", null: false
    t.bigint "author_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "hold_on_reply", default: false, null: false
    t.index ["account_id", "status"], name: "idx_recurring_sched_msgs_on_account_status"
    t.index ["account_id"], name: "index_recurring_scheduled_messages_on_account_id"
    t.index ["author_type", "author_id"], name: "index_recurring_scheduled_messages_on_author"
    t.index ["conversation_id", "status"], name: "idx_recurring_sched_msgs_on_conversation_status"
    t.index ["conversation_id"], name: "index_recurring_scheduled_messages_on_conversation_id"
    t.index ["inbox_id"], name: "index_recurring_scheduled_messages_on_inbox_id"
    t.index ["status"], name: "idx_recurring_sched_msgs_on_status"
  end

  create_table "related_categories", force: :cascade do |t|
    t.bigint "category_id"
    t.bigint "related_category_id"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.index ["category_id", "related_category_id"], name: "index_related_categories_on_category_id_and_related_category_id", unique: true
    t.index ["related_category_id", "category_id"], name: "index_related_categories_on_related_category_id_and_category_id", unique: true
  end

  create_table "reporting_events", force: :cascade do |t|
    t.string "name"
    t.float "value"
    t.integer "account_id"
    t.integer "inbox_id"
    t.integer "user_id"
    t.integer "conversation_id"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.float "value_in_business_hours"
    t.datetime "event_start_time", precision: nil
    t.datetime "event_end_time", precision: nil
    t.index ["account_id", "name", "created_at"], name: "reporting_events__account_id__name__created_at"
    t.index ["account_id", "name", "inbox_id", "created_at"], name: "index_reporting_events_for_response_distribution"
    t.index ["account_id"], name: "index_reporting_events_on_account_id"
    t.index ["conversation_id"], name: "index_reporting_events_on_conversation_id"
    t.index ["created_at"], name: "index_reporting_events_on_created_at"
    t.index ["inbox_id"], name: "index_reporting_events_on_inbox_id"
    t.index ["name"], name: "index_reporting_events_on_name"
    t.index ["user_id"], name: "index_reporting_events_on_user_id"
  end

  create_table "reporting_events_rollups", force: :cascade do |t|
    t.integer "account_id", null: false
    t.date "date", null: false
    t.string "dimension_type", null: false
    t.bigint "dimension_id", null: false
    t.string "metric", null: false
    t.bigint "count", default: 0, null: false
    t.float "sum_value", default: 0.0, null: false
    t.float "sum_value_business_hours", default: 0.0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "date", "dimension_type", "dimension_id", "metric"], name: "index_rollup_unique_key", unique: true
    t.index ["account_id", "dimension_type", "date"], name: "index_rollup_summary"
    t.index ["account_id", "metric", "date"], name: "index_rollup_timeseries"
  end

  create_table "scheduled_messages", force: :cascade do |t|
    t.text "content"
    t.jsonb "template_params", default: {}
    t.datetime "scheduled_at"
    t.integer "status", default: 0, null: false
    t.bigint "account_id", null: false
    t.bigint "conversation_id", null: false
    t.bigint "inbox_id", null: false
    t.string "author_type"
    t.bigint "author_id"
    t.bigint "message_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "recurring_scheduled_message_id"
    t.boolean "hold_on_reply", default: false, null: false
    t.index ["account_id", "status"], name: "index_scheduled_messages_on_account_id_and_status"
    t.index ["account_id"], name: "index_scheduled_messages_on_account_id"
    t.index ["author_type", "author_id", "status"], name: "idx_on_author_type_author_id_status_6997d67ef6"
    t.index ["author_type", "author_id"], name: "index_scheduled_messages_on_author"
    t.index ["conversation_id", "scheduled_at"], name: "index_scheduled_messages_on_conversation_id_and_scheduled_at"
    t.index ["conversation_id", "status"], name: "index_scheduled_messages_on_conversation_id_and_status"
    t.index ["conversation_id"], name: "index_scheduled_messages_on_conversation_id"
    t.index ["inbox_id", "status"], name: "index_scheduled_messages_on_inbox_id_and_status"
    t.index ["inbox_id"], name: "index_scheduled_messages_on_inbox_id"
    t.index ["message_id"], name: "index_scheduled_messages_on_message_id"
    t.index ["recurring_scheduled_message_id"], name: "index_scheduled_messages_on_recurring_scheduled_message_id"
    t.index ["status", "scheduled_at"], name: "index_scheduled_messages_on_status_and_scheduled_at"
  end

  create_table "sla_events", force: :cascade do |t|
    t.bigint "applied_sla_id", null: false
    t.bigint "conversation_id", null: false
    t.bigint "account_id", null: false
    t.bigint "sla_policy_id", null: false
    t.bigint "inbox_id", null: false
    t.integer "event_type"
    t.jsonb "meta", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_sla_events_on_account_id"
    t.index ["applied_sla_id"], name: "index_sla_events_on_applied_sla_id"
    t.index ["conversation_id"], name: "index_sla_events_on_conversation_id"
    t.index ["inbox_id"], name: "index_sla_events_on_inbox_id"
    t.index ["sla_policy_id"], name: "index_sla_events_on_sla_policy_id"
  end

  create_table "sla_policies", force: :cascade do |t|
    t.string "name", null: false
    t.float "first_response_time_threshold"
    t.float "next_response_time_threshold"
    t.boolean "only_during_business_hours", default: false
    t.bigint "account_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "description"
    t.float "resolution_time_threshold"
    t.index ["account_id"], name: "index_sla_policies_on_account_id"
  end

  create_table "taggings", id: :serial, force: :cascade do |t|
    t.integer "tag_id"
    t.string "taggable_type"
    t.integer "taggable_id"
    t.string "tagger_type"
    t.integer "tagger_id"
    t.string "context", limit: 128
    t.datetime "created_at", precision: nil
    t.index ["context"], name: "index_taggings_on_context"
    t.index ["tag_id", "taggable_id", "taggable_type", "context", "tagger_id", "tagger_type"], name: "taggings_idx", unique: true
    t.index ["tag_id"], name: "index_taggings_on_tag_id"
    t.index ["taggable_id", "taggable_type", "context"], name: "index_taggings_on_taggable_id_and_taggable_type_and_context"
    t.index ["taggable_id", "taggable_type", "tagger_id", "context"], name: "taggings_idy"
    t.index ["taggable_id"], name: "index_taggings_on_taggable_id"
    t.index ["taggable_type"], name: "index_taggings_on_taggable_type"
    t.index ["tagger_id", "tagger_type"], name: "index_taggings_on_tagger_id_and_tagger_type"
    t.index ["tagger_id"], name: "index_taggings_on_tagger_id"
  end

  create_table "tags", id: :serial, force: :cascade do |t|
    t.string "name"
    t.integer "taggings_count", default: 0
    t.index "lower((name)::text) gin_trgm_ops", name: "tags_name_trgm_idx", using: :gin
    t.index ["name"], name: "index_tags_on_name", unique: true
  end

  create_table "team_members", force: :cascade do |t|
    t.bigint "team_id", null: false
    t.bigint "user_id", null: false
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.index ["team_id", "user_id"], name: "index_team_members_on_team_id_and_user_id", unique: true
    t.index ["team_id"], name: "index_team_members_on_team_id"
    t.index ["user_id"], name: "index_team_members_on_user_id"
  end

  create_table "teams", force: :cascade do |t|
    t.string "name", null: false
    t.text "description"
    t.boolean "allow_auto_assign", default: true
    t.bigint "account_id", null: false
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.string "icon", default: ""
    t.string "icon_color", default: ""
    t.index ["account_id"], name: "index_teams_on_account_id"
    t.index ["name", "account_id"], name: "index_teams_on_name_and_account_id", unique: true
  end

  create_table "user_sessions", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "client_id", null: false
    t.string "ip_address"
    t.string "user_agent"
    t.string "browser_name"
    t.string "browser_version"
    t.string "device_name"
    t.string "platform_name"
    t.string "platform_version"
    t.string "city"
    t.string "country"
    t.string "country_code"
    t.datetime "last_activity_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id", "client_id"], name: "index_user_sessions_on_user_id_and_client_id", unique: true
    t.index ["user_id"], name: "index_user_sessions_on_user_id"
  end

  create_table "users", id: :serial, force: :cascade do |t|
    t.string "provider", default: "email", null: false
    t.string "uid", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at", precision: nil
    t.datetime "remember_created_at", precision: nil
    t.integer "sign_in_count", default: 0, null: false
    t.datetime "current_sign_in_at", precision: nil
    t.datetime "last_sign_in_at", precision: nil
    t.string "current_sign_in_ip"
    t.string "last_sign_in_ip"
    t.string "confirmation_token"
    t.datetime "confirmed_at", precision: nil
    t.datetime "confirmation_sent_at", precision: nil
    t.string "unconfirmed_email"
    t.string "name", null: false
    t.string "display_name"
    t.string "email"
    t.json "tokens"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.string "pubsub_token"
    t.integer "availability", default: 0
    t.jsonb "ui_settings", default: {}
    t.jsonb "custom_attributes", default: {}
    t.string "type"
    t.text "message_signature"
    t.string "otp_secret"
    t.integer "consumed_timestep"
    t.boolean "otp_required_for_login", default: false, null: false
    t.text "otp_backup_codes"
    t.index "f_unaccent((name)::text) gin_trgm_ops", name: "idx_users_name_unaccent_trgm", using: :gin
    t.index ["email"], name: "index_users_on_email"
    t.index ["otp_required_for_login"], name: "index_users_on_otp_required_for_login"
    t.index ["otp_secret"], name: "index_users_on_otp_secret", unique: true
    t.index ["pubsub_token"], name: "index_users_on_pubsub_token", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
    t.index ["uid", "provider"], name: "index_users_on_uid_and_provider", unique: true
  end

  create_table "webhooks", force: :cascade do |t|
    t.integer "account_id"
    t.integer "inbox_id"
    t.text "url"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.integer "webhook_type", default: 0
    t.jsonb "subscriptions", default: ["conversation_status_changed", "conversation_updated", "conversation_created", "contact_created", "contact_updated", "message_created", "message_updated", "webwidget_triggered"]
    t.string "name"
    t.string "secret"
    t.index ["account_id", "url"], name: "index_webhooks_on_account_id_and_url", unique: true
  end

  create_table "working_hours", force: :cascade do |t|
    t.bigint "inbox_id"
    t.bigint "account_id"
    t.integer "day_of_week", null: false
    t.boolean "closed_all_day", default: false
    t.integer "open_hour"
    t.integer "open_minutes"
    t.integer "close_hour"
    t.integer "close_minutes"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.boolean "open_all_day", default: false
    t.index ["account_id"], name: "index_working_hours_on_account_id"
    t.index ["inbox_id"], name: "index_working_hours_on_inbox_id"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "campaign_recipients", "accounts", on_delete: :cascade
  add_foreign_key "campaign_recipients", "campaigns", on_delete: :cascade
  add_foreign_key "campaign_recipients", "contacts", on_delete: :cascade
  add_foreign_key "campaign_recipients", "inboxes", on_delete: :cascade
  add_foreign_key "captain_assistants", "captain_units", on_delete: :nullify
  add_foreign_key "captain_brands", "accounts"
  add_foreign_key "captain_conversation_insights", "accounts"
  add_foreign_key "captain_conversation_insights", "captain_units"
  add_foreign_key "captain_conversation_insights", "inboxes", name: "fk_rails_inbox_id"
  add_foreign_key "captain_gallery_items", "accounts"
  add_foreign_key "captain_gallery_items", "captain_units"
  add_foreign_key "captain_gallery_items", "inboxes"
  add_foreign_key "captain_gallery_items", "users", column: "created_by_id"
  add_foreign_key "captain_inbox_automations", "accounts"
  add_foreign_key "captain_inbox_automations", "inboxes"
  add_foreign_key "captain_inbox_reminder_settings", "accounts"
  add_foreign_key "captain_inbox_reminder_settings", "inboxes"
  add_foreign_key "captain_inboxes", "captain_units"
  add_foreign_key "captain_notification_templates", "inboxes"
  add_foreign_key "captain_pix_charges", "captain_reservations", column: "reservation_id"
  add_foreign_key "captain_pix_charges", "captain_units", column: "unit_id"
  add_foreign_key "captain_pricing_amounts", "captain_pricing_categories"
  add_foreign_key "captain_pricing_categories", "captain_units"
  add_foreign_key "captain_pricings", "accounts"
  add_foreign_key "captain_pricings", "captain_brands"
  add_foreign_key "captain_reminders", "accounts"
  add_foreign_key "captain_reminders", "contact_inboxes"
  add_foreign_key "captain_reminders", "contacts"
  add_foreign_key "captain_reminders", "conversations"
  add_foreign_key "captain_reminders", "inboxes"
  add_foreign_key "captain_reservations", "accounts"
  add_foreign_key "captain_reservations", "captain_brands"
  add_foreign_key "captain_reservations", "captain_units"
  add_foreign_key "captain_reservations", "contact_inboxes"
  add_foreign_key "captain_reservations", "contacts"
  add_foreign_key "captain_reservations", "conversations"
  add_foreign_key "captain_reservations", "inboxes"
  add_foreign_key "captain_tool_configs", "accounts"
  add_foreign_key "captain_tool_configs", "inboxes"
  add_foreign_key "captain_unit_inboxes", "captain_units", on_delete: :cascade
  add_foreign_key "captain_unit_inboxes", "inboxes", on_delete: :cascade
  add_foreign_key "captain_units", "accounts"
  add_foreign_key "captain_units", "captain_brands"
  add_foreign_key "captain_units", "inboxes"
  add_foreign_key "captain_units", "inboxes", column: "concierge_inbox_id"
  add_foreign_key "group_members", "contacts"
  add_foreign_key "group_members", "contacts", column: "group_contact_id"
  add_foreign_key "inboxes", "portals"
  add_foreign_key "internal_chat_channel_members", "internal_chat_channels"
  add_foreign_key "internal_chat_channel_members", "users", on_delete: :cascade
  add_foreign_key "internal_chat_channel_teams", "internal_chat_channels"
  add_foreign_key "internal_chat_channel_teams", "teams"
  add_foreign_key "internal_chat_channels", "internal_chat_categories", column: "category_id"
  add_foreign_key "internal_chat_channels", "users", column: "created_by_id", on_delete: :nullify
  add_foreign_key "internal_chat_drafts", "internal_chat_channels"
  add_foreign_key "internal_chat_drafts", "users", on_delete: :cascade
  add_foreign_key "internal_chat_message_attachments", "internal_chat_messages"
  add_foreign_key "internal_chat_messages", "accounts", on_delete: :cascade
  add_foreign_key "internal_chat_messages", "internal_chat_channels"
  add_foreign_key "internal_chat_messages", "internal_chat_messages", column: "parent_id"
  add_foreign_key "internal_chat_messages", "users", column: "sender_id", on_delete: :nullify
  add_foreign_key "internal_chat_poll_options", "internal_chat_polls"
  add_foreign_key "internal_chat_poll_votes", "internal_chat_poll_options"
  add_foreign_key "internal_chat_poll_votes", "users", on_delete: :cascade
  add_foreign_key "internal_chat_polls", "internal_chat_messages"
  add_foreign_key "internal_chat_reactions", "internal_chat_messages"
  add_foreign_key "internal_chat_reactions", "users", on_delete: :cascade
  add_foreign_key "messages", "messages", column: "in_reply_to_id"
  add_foreign_key "recurring_scheduled_messages", "accounts"
  add_foreign_key "recurring_scheduled_messages", "conversations"
  add_foreign_key "recurring_scheduled_messages", "inboxes"
  add_foreign_key "scheduled_messages", "accounts"
  add_foreign_key "scheduled_messages", "conversations"
  add_foreign_key "scheduled_messages", "inboxes"
  add_foreign_key "scheduled_messages", "messages"
  add_foreign_key "scheduled_messages", "recurring_scheduled_messages"
  add_foreign_key "user_sessions", "users"
  create_trigger("accounts_after_insert_row_tr", :generated => true, :compatibility => 1).
      on("accounts").
      after(:insert).
      for_each(:row) do
    "execute format('create sequence IF NOT EXISTS conv_dpid_seq_%s', NEW.id);"
  end

  create_trigger("conversations_before_insert_row_tr", :generated => true, :compatibility => 1).
      on("conversations").
      before(:insert).
      for_each(:row) do
    "NEW.display_id := nextval('conv_dpid_seq_' || NEW.account_id);"
  end

  create_trigger("camp_dpid_before_insert", :generated => true, :compatibility => 1).
      on("accounts").
      name("camp_dpid_before_insert").
      after(:insert).
      for_each(:row) do
    "execute format('create sequence IF NOT EXISTS camp_dpid_seq_%s', NEW.id);"
  end

  create_trigger("campaigns_before_insert_row_tr", :generated => true, :compatibility => 1).
      on("campaigns").
      before(:insert).
      for_each(:row) do
    "NEW.display_id := nextval('camp_dpid_seq_' || NEW.account_id);"
  end

end
