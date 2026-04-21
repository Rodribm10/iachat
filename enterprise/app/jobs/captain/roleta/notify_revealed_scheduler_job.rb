# frozen_string_literal: true

# Cron de fallback (a cada 5 min): enfileira NotifyRevealedJob pra qualquer
# draw que foi revelado há >60s e ainda não foi notificado. Cobre cenários onde
# o front não conseguiu chamar o endpoint (browser fechado, rede caiu).
class Captain::Roleta::NotifyRevealedSchedulerJob < ApplicationJob
  DEFAULT_SCHEMA = 'reserva_hotel'

  queue_as :scheduled_jobs

  def perform
    pending = fetch_pending_tokens
    return if pending.blank?

    Rails.logger.info "[NotifyRevealedScheduler] enfileirando #{pending.size} drawn(s)"
    pending.each { |row| Captain::Roleta::NotifyRevealedJob.perform_later(row['token']) }
  end

  private

  def fetch_pending_tokens
    body = {
      :select => 'token',
      :status => 'eq.revealed',
      :notified_at => 'is.null',
      'revealed_at' => "lt.#{1.minute.ago.iso8601}",
      :limit => 100
    }
    supabase_get('roulette_draws', body)
  rescue StandardError => e
    Rails.logger.warn("[NotifyRevealedScheduler] falha: #{e.class} - #{e.message}")
    []
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
