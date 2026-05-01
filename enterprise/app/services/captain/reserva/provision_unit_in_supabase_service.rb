# frozen_string_literal: true

# Faz upsert da Captain::Unit em reserva_hotel.unidades (Supabase reserva-1001).
# Disparado automaticamente após criação da unit (via after_commit) e por rake
# de reconciliação (captain:reprovision_unit_in_supabase).
#
# Pré-requisitos:
# - ENV RESERVA_1001_SUPABASE_URL / _ANON_KEY / _SCHEMA setados
# - Captain::Unit.brand cadastrada com nome igual ao da marcas.nome no Supabase
# - UNIQUE (tenant_id, chatwoot_unit_id) em reserva_hotel.unidades
#
# Idempotente: chamadas repetidas atualizam a mesma row.
class Captain::Reserva::ProvisionUnitInSupabaseService
  DEFAULT_SCHEMA = 'reserva_hotel'
  DEFAULT_TENANT_ID = 1
  # Conta padrão usada quando a unidade ainda não tem id_conta_pagamento próprio.
  # Cada marca pode editar isso direto no Supabase posteriormente.
  DEFAULT_CONTA_PAGAMENTO_ID = 'e227a8b3-480a-46a8-987f-2cca6395760b'

  def initialize(unit:)
    @unit = unit
  end

  def perform # rubocop:disable Metrics/AbcSize
    precheck = preflight_error
    return precheck if precheck

    marca_id = resolve_marca_id
    return error("marca '#{unit.brand.name}' não encontrada em reserva_hotel.marcas") if marca_id.blank?

    row = upsert_unidade(build_payload(marca_id))
    return error('falha ao gravar unidade no Supabase') if row.blank?

    persist_supabase_ids(row)
    Rails.logger.info("[Captain::Reserva::ProvisionUnit] unit=#{unit.id} (#{unit.name}) -> supabase_unit=#{row['id']}")
    { success: true, supabase_unit_id: row['id'] }
  rescue StandardError => e
    Rails.logger.error("[Captain::Reserva::ProvisionUnit] unit=#{unit&.id} #{e.class}: #{e.message}")
    error(e.message)
  end

  def preflight_error
    return error('unit ausente') if unit.blank?
    return error('unit sem brand vinculada') if unit.brand.blank?
    return error('Supabase não configurado (env vars ausentes)') unless supabase_configured?

    nil
  end

  private

  attr_reader :unit

  def error(msg)
    { success: false, error: msg }
  end

  def supabase_configured?
    supabase_url.present? && supabase_key.present?
  end

  def resolve_marca_id
    rows = supabase_get('marcas', { nome: "eq.#{unit.brand.name}", tenant_id: "eq.#{tenant_id}", select: 'id' })
    rows.first&.dig('id')
  end

  # update_columns intencional: pula validações/callbacks pra evitar
  # disparar after_commit em loop (chamado pelo próprio after_commit).
  def persist_supabase_ids(row)
    unit.update_columns( # rubocop:disable Rails/SkipsModelValidations
      supabase_unit_id: row['id'],
      supabase_tenant_id: row['tenant_id'],
      supabase_marca_id: row['id_marca']
    )
  end

  def build_payload(marca_id)
    {
      nome: unit.name,
      id_marca: marca_id,
      id_conta_pagamento: unit.supabase_unit_id.present? ? nil : DEFAULT_CONTA_PAGAMENTO_ID,
      tenant_id: tenant_id,
      chatwoot_unit_id: unit.id,
      categorias_visiveis: Array(unit.visible_suite_categories),
      ativa: true
    }.compact
  end

  def upsert_unidade(payload)
    url = "#{supabase_url}/rest/v1/unidades?on_conflict=tenant_id,chatwoot_unit_id"
    response = http.post(url) do |req|
      apply_upsert_headers(req)
      req.body = payload.to_json
    end
    return nil unless response.success?

    Array(JSON.parse(response.body)).first
  rescue JSON::ParserError
    nil
  end

  def apply_upsert_headers(req)
    req.headers['apikey'] = supabase_key
    req.headers['Authorization'] = "Bearer #{supabase_key}"
    req.headers['Content-Profile'] = supabase_schema
    req.headers['Content-Type'] = 'application/json'
    req.headers['Accept'] = 'application/json'
    req.headers['Accept-Encoding'] = 'identity'
    req.headers['Prefer'] = 'resolution=merge-duplicates,return=representation'
  end

  def supabase_get(table, query)
    url = "#{supabase_url}/rest/v1/#{table}"
    response = http.get(url, query) do |req|
      req.headers['apikey'] = supabase_key
      req.headers['Authorization'] = "Bearer #{supabase_key}"
      req.headers['Accept-Profile'] = supabase_schema
      req.headers['Accept'] = 'application/json'
      req.headers['Accept-Encoding'] = 'identity'
    end
    return [] unless response.success?

    JSON.parse(response.body)
  rescue JSON::ParserError
    []
  end

  def http
    @http ||= Faraday.new do |f|
      f.adapter Faraday.default_adapter
      f.options.timeout = 8
      f.options.open_timeout = 4
    end
  end

  def supabase_url
    ENV.fetch('RESERVA_1001_SUPABASE_URL', nil)&.chomp('/')
  end

  def supabase_key
    ENV.fetch('RESERVA_1001_SUPABASE_ANON_KEY', nil)
  end

  def supabase_schema
    ENV.fetch('RESERVA_1001_SUPABASE_SCHEMA', DEFAULT_SCHEMA)
  end

  def tenant_id
    unit.supabase_tenant_id.presence || DEFAULT_TENANT_ID
  end
end
