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

  def initialize(unit:)
    @unit = unit
  end

  def perform # rubocop:disable Metrics/AbcSize
    precheck = preflight_error
    return precheck if precheck

    marca_id = resolve_marca_id
    return error("marca '#{unit.brand.name}' não encontrada em reserva_hotel.marcas") if marca_id.blank?

    row = upsert_via_rpc(marca_id)
    return error('falha ao gravar unidade no Supabase') if row.blank?

    persist_supabase_ids(row)
    Rails.logger.info("[Captain::Reserva::ProvisionUnit] unit=#{unit.id} (#{unit.name}) -> supabase_unit=#{row['out_id']}")
    { success: true, supabase_unit_id: row['out_id'] }
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
      supabase_unit_id: row['out_id'],
      supabase_tenant_id: row['out_tenant_id'],
      supabase_marca_id: row['out_id_marca']
    )
  end

  # Chama a RPC reserva_hotel.provision_unidade (SECURITY DEFINER) que faz
  # upsert idempotente em unidades bypassando RLS. Anon key tem GRANT EXECUTE.
  def upsert_via_rpc(marca_id)
    response = http.post("#{supabase_url}/rest/v1/rpc/provision_unidade") do |req|
      apply_rpc_headers(req)
      req.body = build_rpc_body(marca_id).to_json
    end
    unless response.success?
      Rails.logger.warn("[ProvisionUnit] RPC status=#{response.status} body=#{response.body}")
      return nil
    end

    Array(JSON.parse(response.body)).first
  rescue JSON::ParserError
    nil
  end

  def build_rpc_body(marca_id)
    {
      p_nome: unit.name,
      p_id_marca: marca_id,
      p_tenant_id: tenant_id,
      p_chatwoot_unit_id: unit.id,
      p_categorias_visiveis: Array(unit.visible_suite_categories)
    }
  end

  def apply_rpc_headers(req)
    req.headers['apikey'] = supabase_key
    req.headers['Authorization'] = "Bearer #{supabase_key}"
    req.headers['Content-Profile'] = supabase_schema
    req.headers['Content-Type'] = 'application/json'
    req.headers['Accept'] = 'application/json'
    req.headers['Accept-Encoding'] = 'identity'
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
