# frozen_string_literal: true

# Relatório semanal de resgates por recepcionista com detecção de anomalias.
# Usado pela tela /captain/roleta (aba relatório) e pode ser chamado por digests.
# rubocop:disable Metrics/MethodLength,Metrics/AbcSize
class Captain::Roleta::WeeklyReportService
  DEFAULT_SCHEMA = 'reserva_hotel'
  DEFAULT_PERIOD_DAYS = 7
  ANOMALY_MIN_COUNT = 5     # abaixo disso nem analisa
  ANOMALY_RATIO = 2.5       # 2.5x a média da equipe flaga

  def initialize(account:, period_days: DEFAULT_PERIOD_DAYS)
    @account = account
    @period_days = period_days
    @period_end = Time.current
    @period_start = @period_end - period_days.days
  end

  def call
    tenant_id = tenant_id_for_account
    return empty_report('tenant_not_mapped') if tenant_id.blank?

    rows = fetch_stats(tenant_id)
    user_map = load_user_names(rows.filter_map { |r| r['receptionist_user_id']&.to_i }.uniq)

    by_receptionist = rows.map { |r| build_row(r, user_map) }
    team_total = by_receptionist.sum { |r| r[:total_redemptions] }
    team_avg = by_receptionist.any? ? (team_total.to_f / by_receptionist.size).round(2) : 0
    threshold = [ANOMALY_MIN_COUNT, (team_avg * ANOMALY_RATIO).ceil].max

    by_receptionist.each do |r|
      r[:anomaly] = r[:total_redemptions] >= threshold && by_receptionist.size > 1
    end

    {
      period_start: @period_start.iso8601,
      period_end: @period_end.iso8601,
      period_days: @period_days,
      team_total: team_total,
      team_avg: team_avg,
      anomaly_threshold: threshold,
      receptionist_count: by_receptionist.size,
      by_receptionist: by_receptionist.sort_by { |r| -r[:total_redemptions] }
    }
  rescue StandardError => e
    Rails.logger.error("[Roleta::WeeklyReportService] falha: #{e.class} - #{e.message}")
    empty_report('error')
  end

  private

  def empty_report(reason)
    {
      period_start: @period_start.iso8601,
      period_end: @period_end.iso8601,
      period_days: @period_days,
      team_total: 0,
      team_avg: 0,
      anomaly_threshold: 0,
      receptionist_count: 0,
      by_receptionist: [],
      note: reason
    }
  end

  def build_row(row, user_map)
    user_id = row['receptionist_user_id']&.to_i
    user = user_map[user_id]
    total_discount = row['total_discount_value'].to_f
    {
      receptionist_user_id: user_id,
      receptionist_name: user&.name || "Usuário ##{user_id}",
      receptionist_email: user&.email,
      total_redemptions: row['total_redemptions'].to_i,
      brinde_count: row['brinde_count'].to_i,
      desconto_count: row['desconto_count'].to_i,
      total_discount_value: total_discount,
      first_redemption: row['first_redemption'],
      last_redemption: row['last_redemption'],
      anomaly: false # setado depois
    }
  end

  def tenant_id_for_account
    unit = Captain::Unit.joins(:inboxes).where(inboxes: { account_id: @account.id }).first
    return nil if unit.blank?

    row = supabase_get('unidades', { chatwoot_unit_id: "eq.#{unit.id}", select: 'tenant_id', limit: 1 }).first
    row&.[]('tenant_id')
  end

  def fetch_stats(tenant_id)
    body = {
      p_tenant_id: tenant_id,
      p_period_start: @period_start.iso8601,
      p_period_end: @period_end.iso8601
    }
    supabase_rpc('roleta_weekly_stats', body)
  end

  def load_user_names(user_ids)
    return {} if user_ids.blank?

    User.where(id: user_ids).index_by(&:id)
  end

  def supabase_get(table, query)
    url = "#{supabase_url}/rest/v1/#{table}"
    response = Faraday.get(url, query) do |req|
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

  def supabase_rpc(fn_name, body)
    url = "#{supabase_url}/rest/v1/rpc/#{fn_name}"
    response = Faraday.post(url) do |req|
      req.headers['apikey'] = supabase_key
      req.headers['Authorization'] = "Bearer #{supabase_key}"
      req.headers['Content-Profile'] = supabase_schema
      req.headers['Content-Type'] = 'application/json'
      req.headers['Accept'] = 'application/json'
      req.headers['Accept-Encoding'] = 'identity'
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
# rubocop:enable Metrics/MethodLength,Metrics/AbcSize
