# frozen_string_literal: true

# Tela de resgate da Roleta da Sorte na recepção.
# Lista cupons revelados dos últimos X dias + permite marcar resgatado.
class Api::V1::Accounts::Captain::RoletaController < Api::V1::Accounts::BaseController
  DEFAULT_SCHEMA = 'reserva_hotel'

  before_action :current_account
  before_action -> { check_authorization(Captain::Assistant) }

  # GET /api/v1/accounts/:account_id/captain/roleta/pending
  # params: days_back (int, default 3), marca_id (uuid, opcional — filtra por marca)
  def pending
    tenant_id = tenant_id_for_account(current_account)
    render json: { pending: [], note: 'tenant_not_mapped' } and return if tenant_id.blank?

    days_back = params[:days_back].to_i
    days_back = 3 if days_back <= 0

    body = {
      p_tenant_id: tenant_id,
      p_days_back: days_back,
      p_limit: 100
    }
    rows = supabase_rpc('list_roulette_pending', body)
    render json: { pending: rows }
  end

  # GET /api/v1/accounts/:account_id/captain/roleta/weekly_report
  # params: period_days (default 7)
  def weekly_report
    days = params[:period_days].to_i
    days = 7 if days <= 0 || days > 90
    report = Captain::Roleta::WeeklyReportService.new(account: current_account, period_days: days).call
    render json: report
  end

  # POST /api/v1/accounts/:account_id/captain/roleta/redeem
  # body: { code: "ABC123", notes: "opcional" }
  def redeem
    code = params[:code].to_s.strip.upcase
    notes = params[:notes]

    if code.blank?
      render json: { success: false, error_code: 'empty_code' }, status: :unprocessable_entity
      return
    end

    result = Captain::Roleta::RedeemService.new(
      code: code,
      receptionist_user: Current.user,
      notes: notes
    ).perform

    if result.success
      render json: { success: true, result: result.to_h }
    else
      render json: { success: false, error_code: result.error_code, result: result.to_h }, status: :unprocessable_entity
    end
  end

  private

  # Resolve tenant_id do Supabase a partir do account do Chatwoot.
  # Usa qualquer inbox desse account que tenha captain_inbox.unit + lookup em reserva_hotel.unidades.
  def tenant_id_for_account(account)
    unit = Captain::Unit.joins(:inboxes).where(inboxes: { account_id: account.id }).first
    return nil if unit.blank?

    row = supabase_get('unidades', { chatwoot_unit_id: "eq.#{unit.id}", select: 'tenant_id', limit: 1 }).first
    row&.[]('tenant_id')
  end

  def supabase_get(table, query)
    url = "#{supabase_url}/rest/v1/#{table}"
    response = Faraday.get(url, query) do |req|
      req.headers['apikey'] = supabase_key
      req.headers['Authorization'] = "Bearer #{supabase_key}"
      req.headers['Accept-Profile'] = supabase_schema
      req.headers['Accept'] = 'application/json'
    end
    return [] unless response.success?

    JSON.parse(response.body)
  rescue JSON::ParserError
    []
  end

  def supabase_rpc(fn_name, body)
    url = "#{supabase_url}/rest/v1/rpc/#{fn_name}"
    response = Faraday.post(url) do |req|
      req.headers['apikey'] = supabase_key
      req.headers['Authorization'] = "Bearer #{supabase_key}"
      req.headers['Content-Profile'] = supabase_schema
      req.headers['Content-Type'] = 'application/json'
      req.headers['Accept'] = 'application/json'
      req.body = body.to_json
    end
    return [] unless response.success?

    JSON.parse(response.body)
  rescue JSON::ParserError
    []
  end

  def supabase_url
    ENV.fetch('RESERVA_1001_SUPABASE_URL').chomp('/')
  end

  def supabase_key
    ENV.fetch('RESERVA_1001_SUPABASE_ANON_KEY')
  end

  def supabase_schema
    ENV.fetch('RESERVA_1001_SUPABASE_SCHEMA', DEFAULT_SCHEMA)
  end
end
