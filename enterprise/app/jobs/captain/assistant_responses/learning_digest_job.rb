# Entrega o resumo semanal do ciclo de aprendizado no mesmo canal do CEO Digest.
#
# Config por conta em account.custom_attributes['ceo_digest'] (reaproveitada) ou
# fallback global CEO_DIGEST_MATTERMOST_WEBHOOK_URL.
class Captain::AssistantResponses::LearningDigestJob < ApplicationJob
  queue_as :scheduled_jobs

  TIMEOUT_SECONDS = 10

  def perform(account_id = nil, period_start = nil, period_end = nil)
    period_end = (period_end || Date.yesterday).to_date
    period_start = (period_start || (period_end - 6.days)).to_date

    scope = account_id ? Account.where(id: account_id) : Account.all
    scope.find_each { |account| deliver_for(account, period_start, period_end) }
  end

  private

  def deliver_for(account, period_start, period_end)
    digest = build_digest(account, period_start, period_end)
    return if digest[:by_assistant].empty?

    webhook_url = webhook_url_for(account)
    return Rails.logger.info("[Captain::LearningDigest] no webhook for account ##{account.id}") if webhook_url.blank?

    post(webhook_url, format_text(digest), channel_for(account))
  rescue StandardError => e
    Rails.logger.error("[Captain::LearningDigest] account ##{account.id}: #{e.class} #{e.message}")
  end

  def build_digest(account, period_start, period_end)
    Captain::AssistantResponses::LearningDigestService.new(
      account: account, period_start: period_start, period_end: period_end
    ).call
  end

  def format_text(digest)
    lines = [I18n.t('captain.learning_digest.header',
                    period_start: digest[:period_start].strftime('%d/%m'),
                    period_end: digest[:period_end].strftime('%d/%m'))]

    digest[:by_assistant].each { |row| lines << format_row(row) }
    lines << ''
    lines << I18n.t('captain.learning_digest.footer', count: digest[:totals][:aguardando_humano])
    lines.join("\n")
  end

  def format_row(row)
    I18n.t(
      'captain.learning_digest.assistant_line',
      name: row[:assistant_name],
      learned: row[:aprendidas],
      trial: row[:em_quarentena],
      promoted: row[:promovidas],
      retired: row[:aposentadas],
      pending: row[:aguardando_humano]
    )
  end

  def post(webhook_url, text, channel)
    payload = { username: 'Captain Aprendizado', icon_emoji: ':books:', text: text }
    payload[:channel] = channel if channel.present?

    response = HTTParty.post(
      webhook_url,
      body: payload.to_json,
      headers: { 'Content-Type' => 'application/json' },
      timeout: TIMEOUT_SECONDS
    )

    Rails.logger.error("[Captain::LearningDigest] delivery failed #{response.code}") unless response.success?
    response.success?
  end

  def digest_config(account)
    account.custom_attributes&.dig('ceo_digest') || {}
  end

  def webhook_url_for(account)
    digest_config(account)['mattermost_webhook_url'].presence ||
      ENV.fetch('CEO_DIGEST_MATTERMOST_WEBHOOK_URL', nil)
  end

  def channel_for(account)
    digest_config(account)['mattermost_channel'].presence
  end
end
