class DropDeadForkTables < ActiveRecord::Migration[7.1]
  # Derruba 25 tabelas confirmadas VAZIAS em producao (auditoria de 22/08/2026,
  # docs/auditoria/2026-08-22-auditoria-fork.md). Tres grupos:
  #
  #   1. Orfas de nascenca — nunca tiveram model Ruby nem uma unica citacao do
  #      nome da tabela em app/, enterprise/ ou lib/. Inclui a familia
  #      captain_prompt_* (versionamento de prompt que nunca ganhou codigo) e o
  #      subsistema jasmine_* (RAG substituido pelo captain_documents).
  #   2. Lifecycle — codigo existia e estava ligado, mas nunca rodou:
  #      0 regras e 0 entregas em producao. A unica linha de
  #      captain_lifecycle_configs era o default criado em 25/04/2026, sem
  #      nenhum campo customizado.
  #   3. Memorias de contato e report snapshots — 0 linhas; o snapshot era
  #      gravador sem leitor e sem cron.
  #
  # IMPORTANTE — ordem de deploy: subir o CODIGO primeiro e so depois rodar
  # esta migration. O codigo novo nao toca em nenhuma destas tabelas, entao
  # nesse intervalo um rollback de imagem continua funcionando.
  def up
    # As FKs internas ao conjunto saem antes, senao o Postgres recusa o
    # drop por dependencia (ex.: captain_prompt_audit_events aponta pra
    # captain_prompt_versions). Nenhuma tabela que sobrevive aponta pra
    # este conjunto — verificado contra o schema.
    remove_foreign_key :captain_assets, :captain_suites, if_exists: true
    remove_foreign_key :captain_lifecycle_deliveries, :captain_lifecycle_rules, column: :lifecycle_rule_id, if_exists: true
    remove_foreign_key :captain_prompt_audit_events, :captain_prompt_profiles, column: :prompt_profile_id, if_exists: true
    remove_foreign_key :captain_prompt_audit_events, :captain_prompt_versions, column: :prompt_version_id, if_exists: true
    remove_foreign_key :captain_prompt_block_versions, :captain_prompt_blocks, column: :prompt_block_id, if_exists: true
    remove_foreign_key :captain_prompt_blocks, :captain_prompt_profiles, column: :prompt_profile_id, if_exists: true
    remove_foreign_key :captain_prompt_improvement_cases, :captain_prompt_profiles, column: :prompt_profile_id, if_exists: true
    remove_foreign_key :captain_prompt_profiles, :captain_prompt_versions, column: :active_version_id, if_exists: true
    remove_foreign_key :captain_prompt_versions, :captain_prompt_improvement_cases, column: :source_case_id, if_exists: true
    remove_foreign_key :captain_prompt_versions, :captain_prompt_profiles, column: :prompt_profile_id, if_exists: true
    remove_foreign_key :jasmine_document_chunks, :jasmine_collections, column: :collection_id, if_exists: true
    remove_foreign_key :jasmine_document_chunks, :jasmine_documents, column: :document_id, if_exists: true
    remove_foreign_key :jasmine_documents, :jasmine_collections, column: :collection_id, if_exists: true
    remove_foreign_key :jasmine_inbox_collections, :jasmine_collections, column: :collection_id, if_exists: true
    remove_foreign_key :whatsapp_campaign_hits, :whatsapp_campaigns, column: :campaign_id, if_exists: true

    drop_table :captain_assets, if_exists: true
    drop_table :captain_suites, if_exists: true
    drop_table :whatsapp_campaign_hits, if_exists: true
    drop_table :whatsapp_campaigns, if_exists: true
    drop_table :jasmine_document_chunks, if_exists: true
    drop_table :jasmine_documents, if_exists: true
    drop_table :jasmine_inbox_collections, if_exists: true
    drop_table :jasmine_collections, if_exists: true
    drop_table :jasmine_inbox_settings, if_exists: true
    drop_table :jasmine_tool_configs, if_exists: true
    drop_table :captain_prompt_block_versions, if_exists: true
    drop_table :captain_prompt_blocks, if_exists: true
    drop_table :captain_prompt_versions, if_exists: true
    drop_table :captain_prompt_profiles, if_exists: true
    drop_table :captain_prompt_audit_events, if_exists: true
    drop_table :captain_prompt_improvement_cases, if_exists: true
    drop_table :captain_extras, if_exists: true
    drop_table :captain_configurations, if_exists: true
    drop_table :conversation_crm_insights, if_exists: true
    drop_table :frequent_questions, if_exists: true
    drop_table :captain_lifecycle_deliveries, if_exists: true
    drop_table :captain_lifecycle_rules, if_exists: true
    drop_table :captain_lifecycle_configs, if_exists: true
    drop_table :captain_contact_memories, if_exists: true
    drop_table :captain_report_snapshots, if_exists: true
  end

  # Reversivel de proposito: todas estavam vazias, entao recriar a estrutura
  # devolve o banco ao estado anterior sem perda de dado.
  def down
    create_table 'captain_report_snapshots', force: :cascade do |t|
      t.bigint 'account_id', null: false
      t.bigint 'captain_unit_id'
      t.date 'snapshot_date', null: false
      t.jsonb 'data', default: {}, null: false
      t.datetime 'created_at', null: false
      t.datetime 'updated_at', null: false
      t.index %w[account_id snapshot_date], name: 'index_captain_report_snapshots_on_account_id_and_snapshot_date'
      t.index ['account_id'], name: 'index_captain_report_snapshots_on_account_id'
      t.index %w[captain_unit_id snapshot_date], name: 'idx_captain_snapshots_unique_date', unique: true
      t.index ['captain_unit_id'], name: 'index_captain_report_snapshots_on_captain_unit_id'
    end

    create_table 'captain_contact_memories', force: :cascade do |t|
      t.bigint 'account_id', null: false
      t.bigint 'contact_id', null: false
      t.string 'memory_type', null: false
      t.text 'content', null: false
      t.text 'evidence', null: false
      t.float 'confidence', null: false
      t.string 'scope', default: 'global', null: false
      t.vector 'embedding', limit: 1536
      t.bigint 'source_conversation_id'
      t.bigint 'source_unit_id'
      t.bigint 'source_inbox_id'
      t.datetime 'expires_at'
      t.datetime 'last_verified_at', null: false
      t.datetime 'superseded_at'
      t.bigint 'superseded_by_id'
      t.datetime 'deleted_at'
      t.jsonb 'metadata', default: {}, null: false
      t.datetime 'created_at', null: false
      t.datetime 'updated_at', null: false
      t.index %w[account_id contact_id], name: 'idx_ccm_recall', where: '((deleted_at IS NULL) AND (superseded_at IS NULL))'
      t.index ['account_id'], name: 'index_captain_contact_memories_on_account_id'
      t.index ['contact_id'], name: 'index_captain_contact_memories_on_contact_id'
      t.index ['deleted_at'], name: 'idx_ccm_hard_delete', where: '(deleted_at IS NOT NULL)'
      t.index ['embedding'], name: 'idx_ccm_embedding', opclass: :vector_cosine_ops, using: :ivfflat
      t.index ['source_conversation_id'], name: 'idx_ccm_source_conversation'
      t.index %w[source_unit_id memory_type created_at], name: 'idx_ccm_analytics'
      t.index ['superseded_by_id'], name: 'idx_ccm_superseded', where: '(superseded_at IS NOT NULL)'
    end

    create_table 'captain_lifecycle_configs', force: :cascade do |t|
      t.bigint 'account_id', null: false
      t.boolean 'quiet_hours_enabled', default: false, null: false
      t.time 'quiet_hours_from', default: '2000-01-01 23:00:00', null: false
      t.time 'quiet_hours_to', default: '2000-01-01 08:00:00', null: false
      t.integer 'min_interval_minutes', default: 30, null: false
      t.boolean 'pause_on_customer_reply', default: false, null: false
      t.integer 'pause_on_customer_reply_within_minutes', default: 60, null: false
      t.bigint 'opt_out_label_id'
      t.datetime 'created_at', null: false
      t.datetime 'updated_at', null: false
      t.index ['account_id'], name: 'index_captain_lifecycle_configs_on_account_id', unique: true
      t.index ['opt_out_label_id'], name: 'index_captain_lifecycle_configs_on_opt_out_label_id'
    end

    create_table 'captain_lifecycle_rules', force: :cascade do |t|
      t.bigint 'account_id', null: false
      t.string 'name', null: false
      t.text 'description'
      t.boolean 'enabled', default: true, null: false
      t.string 'event', null: false
      t.integer 'offset_minutes', default: 0, null: false
      t.jsonb 'filters', default: {}, null: false
      t.string 'message_type', default: 'text', null: false
      t.text 'message_body', null: false
      t.jsonb 'message_payload'
      t.integer 'priority', default: 50, null: false
      t.bigint 'created_by_user_id'
      t.datetime 'created_at', null: false
      t.datetime 'updated_at', null: false
      t.index %w[account_id enabled event], name: 'idx_on_account_id_enabled_event_2d8b8a9942'
      t.index ['account_id'], name: 'index_captain_lifecycle_rules_on_account_id'
      t.index ['created_by_user_id'], name: 'index_captain_lifecycle_rules_on_created_by_user_id'
    end

    create_table 'captain_lifecycle_deliveries', force: :cascade do |t|
      t.bigint 'account_id', null: false
      t.bigint 'lifecycle_rule_id'
      t.bigint 'captain_reservation_id', null: false
      t.bigint 'conversation_id'
      t.bigint 'message_id'
      t.bigint 'inbox_id'
      t.datetime 'fire_at', null: false
      t.datetime 'sent_at'
      t.string 'status', default: 'scheduled', null: false
      t.string 'skip_reason'
      t.text 'failure_reason'
      t.text 'rendered_body'
      t.string 'origin', default: 'scheduled_lifecycle', null: false
      t.datetime 'created_at', null: false
      t.datetime 'updated_at', null: false
      t.index %w[account_id status fire_at], name: 'idx_lifecycle_deliveries_dashboard'
      t.index ['account_id'], name: 'index_captain_lifecycle_deliveries_on_account_id'
      t.index %w[captain_reservation_id origin status], name: 'idx_lifecycle_deliveries_cap_check'
      t.index ['captain_reservation_id'], name: 'idx_lifecycle_deliveries_reservation'
      t.index ['conversation_id'], name: 'index_captain_lifecycle_deliveries_on_conversation_id'
      t.index ['fire_at'], name: 'idx_lifecycle_deliveries_scheduled', where: "((status)::text = 'scheduled'::text)"
      t.index ['inbox_id'], name: 'index_captain_lifecycle_deliveries_on_inbox_id'
      t.index ['lifecycle_rule_id'], name: 'idx_lifecycle_deliveries_rule'
      t.index ['message_id'], name: 'index_captain_lifecycle_deliveries_on_message_id'
    end

    create_table 'frequent_questions', force: :cascade do |t|
      t.bigint 'account_id', null: false
      t.string 'label'
      t.string 'question_text'
      t.integer 'occurrence_count'
      t.date 'cluster_date'
      t.datetime 'created_at', null: false
      t.datetime 'updated_at', null: false
      t.index ['account_id'], name: 'index_frequent_questions_on_account_id'
    end

    create_table 'conversation_crm_insights', force: :cascade do |t|
      t.bigint 'conversation_id', null: false
      t.bigint 'contact_id', null: false
      t.text 'summary_text'
      t.jsonb 'structured_data', default: {}
      t.integer 'contact_sessions_count', default: 0, null: false
      t.datetime 'last_contact_at'
      t.datetime 'created_at', null: false
      t.datetime 'updated_at', null: false
      t.bigint 'account_id'
      t.datetime 'generated_at'
      t.bigint 'range_from_message_id'
      t.bigint 'range_to_message_id'
      t.string 'status', default: 'success'
      t.text 'error_message'
      t.string 'schema_version'
      t.string 'model'
      t.float 'confidence'
      t.index ['account_id'], name: 'index_conversation_crm_insights_on_account_id'
      t.index ['contact_id'], name: 'index_conversation_crm_insights_on_contact_id'
      t.index %w[conversation_id generated_at], name: 'idx_on_conversation_id_generated_at_44d5836366'
      t.index ['conversation_id'], name: 'index_conversation_crm_insights_on_conversation_id'
      t.index ['status'], name: 'index_conversation_crm_insights_on_status'
    end

    create_table 'captain_configurations', force: :cascade do |t|
      t.bigint 'account_id', null: false
      t.string 'title', default: 'Reserva Rápida'
      t.string 'subtitle', default: 'Agende sua estadia com praticidade'
      t.string 'logo_url'
      t.string 'primary_color', default: '#1E90FF'
      t.string 'secondary_color', default: '#1B3B5F'
      t.boolean 'active', default: true
      t.datetime 'created_at', null: false
      t.datetime 'updated_at', null: false
      t.string 'phone_number'
      t.index ['account_id'], name: 'index_captain_configurations_on_account_id'
    end

    create_table 'captain_extras', force: :cascade do |t|
      t.bigint 'account_id', null: false
      t.string 'title', null: false
      t.text 'description'
      t.decimal 'price', precision: 10, scale: 2, null: false
      t.string 'image_url'
      t.string 'category'
      t.string 'tag'
      t.boolean 'active', default: true
      t.integer 'order', default: 0
      t.datetime 'created_at', null: false
      t.datetime 'updated_at', null: false
      t.index ['account_id'], name: 'index_captain_extras_on_account_id'
    end

    create_table 'captain_prompt_improvement_cases', force: :cascade do |t|
      t.bigint 'prompt_profile_id', null: false
      t.text 'customer_message', null: false
      t.text 'agent_actual_response'
      t.text 'expected_response', null: false
      t.string 'failure_type'
      t.text 'diagnosis'
      t.text 'proposed_patch'
      t.decimal 'confidence_score', precision: 5, scale: 4
      t.string 'decision'
      t.bigint 'decided_by_id'
      t.datetime 'created_at', null: false
      t.datetime 'updated_at', null: false
      t.index ['created_at'], name: 'index_captain_prompt_improvement_cases_on_created_at'
      t.index ['decided_by_id'], name: 'index_captain_prompt_improvement_cases_on_decided_by_id'
      t.index ['decision'], name: 'index_captain_prompt_improvement_cases_on_decision'
      t.index ['failure_type'], name: 'index_captain_prompt_improvement_cases_on_failure_type'
      t.index ['prompt_profile_id'], name: 'index_captain_prompt_improvement_cases_on_prompt_profile_id'
    end

    create_table 'captain_prompt_audit_events', force: :cascade do |t|
      t.bigint 'prompt_profile_id', null: false
      t.bigint 'prompt_version_id'
      t.string 'event_type', null: false
      t.jsonb 'payload_json', default: {}, null: false
      t.bigint 'actor_id'
      t.datetime 'created_at', null: false
      t.datetime 'updated_at', null: false
      t.index ['actor_id'], name: 'index_captain_prompt_audit_events_on_actor_id'
      t.index ['created_at'], name: 'index_captain_prompt_audit_events_on_created_at'
      t.index ['event_type'], name: 'index_captain_prompt_audit_events_on_event_type'
      t.index ['prompt_profile_id'], name: 'index_captain_prompt_audit_events_on_prompt_profile_id'
      t.index ['prompt_version_id'], name: 'index_captain_prompt_audit_events_on_prompt_version_id'
    end

    create_table 'captain_prompt_profiles', force: :cascade do |t|
      t.bigint 'account_id', null: false
      t.bigint 'captain_assistant_id', null: false
      t.string 'name', null: false
      t.bigint 'active_version_id'
      t.datetime 'created_at', null: false
      t.datetime 'updated_at', null: false
      t.index ['account_id'], name: 'index_captain_prompt_profiles_on_account_id'
      t.index ['active_version_id'], name: 'index_captain_prompt_profiles_on_active_version_id'
      t.index ['captain_assistant_id'], name: 'index_captain_prompt_profiles_on_captain_assistant_id', unique: true
    end

    create_table 'captain_prompt_versions', force: :cascade do |t|
      t.bigint 'prompt_profile_id', null: false
      t.integer 'version_number', null: false
      t.text 'content', null: false
      t.text 'change_summary'
      t.text 'change_reason'
      t.bigint 'source_case_id'
      t.string 'created_by_type'
      t.bigint 'created_by_id'
      t.string 'status', default: 'draft', null: false
      t.datetime 'created_at', null: false
      t.datetime 'updated_at', null: false
      t.index ['created_at'], name: 'index_captain_prompt_versions_on_created_at'
      t.index ['created_by_id'], name: 'index_captain_prompt_versions_on_created_by_id'
      t.index %w[prompt_profile_id version_number], name: 'idx_captain_prompt_versions_profile_version', unique: true
      t.index ['prompt_profile_id'], name: 'idx_captain_prompt_versions_single_active_per_profile', unique: true,
                                     where: "((status)::text = 'active'::text)"
      t.index ['prompt_profile_id'], name: 'index_captain_prompt_versions_on_prompt_profile_id'
      t.index ['source_case_id'], name: 'index_captain_prompt_versions_on_source_case_id'
      t.index ['status'], name: 'index_captain_prompt_versions_on_status'
    end

    create_table 'captain_prompt_blocks', force: :cascade do |t|
      t.bigint 'prompt_profile_id', null: false
      t.string 'key', null: false
      t.string 'title'
      t.text 'description'
      t.integer 'order_index', default: 0, null: false
      t.datetime 'created_at', null: false
      t.datetime 'updated_at', null: false
      t.index %w[prompt_profile_id key], name: 'index_captain_prompt_blocks_on_prompt_profile_id_and_key', unique: true
      t.index ['prompt_profile_id'], name: 'index_captain_prompt_blocks_on_prompt_profile_id'
    end

    create_table 'captain_prompt_block_versions', force: :cascade do |t|
      t.bigint 'prompt_block_id', null: false
      t.integer 'version_number', null: false
      t.text 'content', null: false
      t.string 'status', default: 'draft', null: false
      t.string 'change_summary'
      t.string 'change_reason'
      t.string 'author_type'
      t.bigint 'author_id'
      t.datetime 'created_at', null: false
      t.datetime 'updated_at', null: false
      t.index %w[prompt_block_id status], name: 'idx_cp_prompt_blk_vers_on_blk_id_and_status'
      t.index %w[prompt_block_id version_number], name: 'idx_cp_prompt_blk_vers_on_blk_id_and_ver_num', unique: true
      t.index ['prompt_block_id'], name: 'index_captain_prompt_block_versions_on_prompt_block_id'
    end

    create_table 'jasmine_tool_configs', force: :cascade do |t|
      t.bigint 'account_id', null: false
      t.bigint 'inbox_id', null: false
      t.string 'tool_key', null: false
      t.boolean 'is_enabled', default: false, null: false
      t.string 'plug_play_id'
      t.text 'plug_play_token'
      t.datetime 'last_tested_at'
      t.integer 'last_test_status'
      t.text 'last_test_error'
      t.integer 'last_test_duration_ms'
      t.datetime 'created_at', null: false
      t.datetime 'updated_at', null: false
      t.index %w[account_id inbox_id tool_key], name: 'index_jasmine_tools_on_account_inbox_key', unique: true
      t.index ['account_id'], name: 'index_jasmine_tool_configs_on_account_id'
      t.index ['inbox_id'], name: 'index_jasmine_tool_configs_on_inbox_id'
      t.index ['tool_key'], name: 'index_jasmine_tool_configs_on_tool_key'
    end

    create_table 'jasmine_inbox_settings', force: :cascade do |t|
      t.bigint 'account_id', null: false
      t.bigint 'inbox_id', null: false
      t.string 'name', default: 'Jasmine'
      t.text 'system_prompt'
      t.boolean 'is_enabled', default: false
      t.integer 'mode', default: 0
      t.datetime 'created_at', null: false
      t.datetime 'updated_at', null: false
      t.text 'playbook_prompt'
      t.float 'rag_distance_threshold', default: 0.35
      t.integer 'rag_max_results', default: 3
      t.string 'model', default: 'gpt-4o-mini'
      t.float 'temperature', default: 0.7
      t.jsonb 'intent_keywords', default: {}
      t.index %w[account_id inbox_id], name: 'index_jasmine_inbox_settings_on_account_id_and_inbox_id', unique: true
      t.index ['account_id'], name: 'index_jasmine_inbox_settings_on_account_id'
      t.index ['inbox_id'], name: 'index_jasmine_inbox_settings_on_inbox_id'
    end

    create_table 'jasmine_collections', force: :cascade do |t|
      t.bigint 'account_id', null: false
      t.string 'name', null: false
      t.text 'description'
      t.bigint 'owner_inbox_id'
      t.integer 'visibility', default: 0
      t.boolean 'is_active', default: true
      t.datetime 'created_at', null: false
      t.datetime 'updated_at', null: false
      t.index %w[account_id owner_inbox_id], name: 'index_jasmine_collections_on_account_id_and_owner_inbox_id'
      t.index %w[account_id visibility], name: 'index_jasmine_collections_on_account_id_and_visibility'
      t.index ['account_id'], name: 'index_jasmine_collections_on_account_id'
      t.index ['owner_inbox_id'], name: 'index_jasmine_collections_on_owner_inbox_id'
    end

    create_table 'jasmine_inbox_collections', force: :cascade do |t|
      t.bigint 'account_id', null: false
      t.bigint 'inbox_id', null: false
      t.bigint 'collection_id', null: false
      t.boolean 'is_enabled', default: true
      t.integer 'priority', default: 0
      t.datetime 'created_at', null: false
      t.datetime 'updated_at', null: false
      t.index %w[account_id collection_id], name: 'idx_on_account_id_collection_id_3011aaebad'
      t.index %w[account_id inbox_id collection_id], name: 'index_jasmine_inbox_collections_uniqueness', unique: true
      t.index %w[account_id inbox_id], name: 'index_jasmine_inbox_collections_on_account_id_and_inbox_id'
      t.index ['account_id'], name: 'index_jasmine_inbox_collections_on_account_id'
      t.index ['collection_id'], name: 'index_jasmine_inbox_collections_on_collection_id'
      t.index ['inbox_id'], name: 'index_jasmine_inbox_collections_on_inbox_id'
    end

    create_table 'jasmine_documents', force: :cascade do |t|
      t.bigint 'account_id', null: false
      t.bigint 'collection_id', null: false
      t.string 'title'
      t.text 'content'
      t.jsonb 'metadata', default: {}
      t.integer 'source_type', default: 0
      t.integer 'status', default: 0
      t.text 'error_message'
      t.datetime 'created_at', null: false
      t.datetime 'updated_at', null: false
      t.index %w[account_id collection_id status], name: 'index_jasmine_docs_on_acc_coll_status'
      t.index ['account_id'], name: 'index_jasmine_documents_on_account_id'
      t.index ['collection_id'], name: 'index_jasmine_documents_on_collection_id'
    end

    create_table 'jasmine_document_chunks', force: :cascade do |t|
      t.bigint 'account_id', null: false
      t.bigint 'collection_id', null: false
      t.bigint 'document_id', null: false
      t.text 'content'
      t.jsonb 'metadata', default: {}
      t.vector 'embedding', limit: 1536
      t.datetime 'created_at', null: false
      t.datetime 'updated_at', null: false
      t.index %w[account_id collection_id document_id], name: 'index_jasmine_chunks_on_acc_coll_doc'
      t.index ['account_id'], name: 'index_jasmine_document_chunks_on_account_id'
      t.index ['collection_id'], name: 'index_jasmine_document_chunks_on_collection_id'
      t.index ['document_id'], name: 'index_jasmine_document_chunks_on_document_id'
      t.index ['embedding'], name: 'index_jasmine_document_chunks_on_embedding', opclass: :vector_cosine_ops, using: :hnsw
    end

    create_table 'whatsapp_campaigns', force: :cascade do |t|
      t.bigint 'account_id', null: false
      t.string 'name', null: false
      t.string 'slug', null: false
      t.string 'phone', null: false
      t.string 'default_message'
      t.boolean 'active', default: true
      t.datetime 'created_at', null: false
      t.datetime 'updated_at', null: false
      t.index ['account_id'], name: 'index_whatsapp_campaigns_on_account_id'
      t.index ['slug'], name: 'index_whatsapp_campaigns_on_slug', unique: true
    end

    create_table 'whatsapp_campaign_hits', force: :cascade do |t|
      t.bigint 'campaign_id', null: false
      t.string 'ip'
      t.string 'user_agent'
      t.datetime 'timestamp'
      t.text 'referer'
      t.string 'utm_source'
      t.string 'utm_medium'
      t.string 'utm_campaign'
      t.string 'utm_term'
      t.string 'utm_content'
      t.string 'country_code'
      t.string 'city'
      t.index %w[campaign_id timestamp], name: 'index_whatsapp_campaign_hits_on_campaign_id_and_timestamp'
      t.index ['campaign_id'], name: 'index_whatsapp_campaign_hits_on_campaign_id'
      t.index ['timestamp'], name: 'index_whatsapp_campaign_hits_on_timestamp'
    end

    create_table 'captain_suites', force: :cascade do |t|
      t.bigint 'account_id', null: false
      t.string 'name'
      t.string 'category'
      t.jsonb 'unit_ids'
      t.string 'api_id'
      t.datetime 'created_at', null: false
      t.datetime 'updated_at', null: false
      t.index ['account_id'], name: 'index_captain_suites_on_account_id'
      t.index ['category'], name: 'index_captain_suites_on_category'
    end

    create_table 'captain_assets', force: :cascade do |t|
      t.bigint 'account_id', null: false
      t.string 'name', null: false
      t.datetime 'created_at', null: false
      t.datetime 'updated_at', null: false
      t.bigint 'captain_suite_id'
      t.index %w[account_id name], name: 'index_captain_assets_on_account_id_and_name', unique: true
      t.index ['account_id'], name: 'index_captain_assets_on_account_id'
      t.index ['captain_suite_id'], name: 'index_captain_assets_on_captain_suite_id'
    end

    add_foreign_key 'captain_assets', 'accounts'
    add_foreign_key 'captain_assets', 'captain_suites'
    add_foreign_key 'captain_configurations', 'accounts'
    add_foreign_key 'captain_contact_memories', 'accounts', on_delete: :cascade
    add_foreign_key 'captain_contact_memories', 'contacts', on_delete: :cascade
    add_foreign_key 'captain_extras', 'accounts'
    add_foreign_key 'captain_lifecycle_configs', 'accounts'
    add_foreign_key 'captain_lifecycle_configs', 'labels', column: 'opt_out_label_id'
    add_foreign_key 'captain_lifecycle_deliveries', 'accounts'
    add_foreign_key 'captain_lifecycle_deliveries', 'captain_lifecycle_rules', column: 'lifecycle_rule_id'
    add_foreign_key 'captain_lifecycle_deliveries', 'captain_reservations'
    add_foreign_key 'captain_lifecycle_deliveries', 'conversations'
    add_foreign_key 'captain_lifecycle_deliveries', 'inboxes'
    add_foreign_key 'captain_lifecycle_deliveries', 'messages'
    add_foreign_key 'captain_lifecycle_rules', 'accounts'
    add_foreign_key 'captain_lifecycle_rules', 'users', column: 'created_by_user_id'
    add_foreign_key 'captain_prompt_audit_events', 'captain_prompt_profiles', column: 'prompt_profile_id'
    add_foreign_key 'captain_prompt_audit_events', 'captain_prompt_versions', column: 'prompt_version_id'
    add_foreign_key 'captain_prompt_block_versions', 'captain_prompt_blocks', column: 'prompt_block_id'
    add_foreign_key 'captain_prompt_blocks', 'captain_prompt_profiles', column: 'prompt_profile_id'
    add_foreign_key 'captain_prompt_improvement_cases', 'captain_prompt_profiles', column: 'prompt_profile_id'
    add_foreign_key 'captain_prompt_profiles', 'accounts'
    add_foreign_key 'captain_prompt_profiles', 'captain_assistants'
    add_foreign_key 'captain_prompt_profiles', 'captain_prompt_versions', column: 'active_version_id'
    add_foreign_key 'captain_prompt_versions', 'captain_prompt_improvement_cases', column: 'source_case_id'
    add_foreign_key 'captain_prompt_versions', 'captain_prompt_profiles', column: 'prompt_profile_id'
    add_foreign_key 'captain_report_snapshots', 'accounts'
    add_foreign_key 'captain_report_snapshots', 'captain_units'
    add_foreign_key 'captain_suites', 'accounts'
    add_foreign_key 'conversation_crm_insights', 'accounts'
    add_foreign_key 'conversation_crm_insights', 'contacts'
    add_foreign_key 'conversation_crm_insights', 'conversations'
    add_foreign_key 'frequent_questions', 'accounts'
    add_foreign_key 'jasmine_collections', 'accounts'
    add_foreign_key 'jasmine_collections', 'inboxes', column: 'owner_inbox_id'
    add_foreign_key 'jasmine_document_chunks', 'accounts'
    add_foreign_key 'jasmine_document_chunks', 'jasmine_collections', column: 'collection_id'
    add_foreign_key 'jasmine_document_chunks', 'jasmine_documents', column: 'document_id'
    add_foreign_key 'jasmine_documents', 'accounts'
    add_foreign_key 'jasmine_documents', 'jasmine_collections', column: 'collection_id'
    add_foreign_key 'jasmine_inbox_collections', 'accounts'
    add_foreign_key 'jasmine_inbox_collections', 'inboxes'
    add_foreign_key 'jasmine_inbox_collections', 'jasmine_collections', column: 'collection_id'
    add_foreign_key 'jasmine_inbox_settings', 'accounts'
    add_foreign_key 'jasmine_inbox_settings', 'inboxes'
    add_foreign_key 'jasmine_tool_configs', 'accounts'
    add_foreign_key 'jasmine_tool_configs', 'inboxes'
    add_foreign_key 'whatsapp_campaign_hits', 'whatsapp_campaigns', column: 'campaign_id'
    add_foreign_key 'whatsapp_campaigns', 'accounts'
  end
end
