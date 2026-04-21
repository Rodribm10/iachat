# Gera e entrega o CEO Digest semanal para cada conta que tiver configurado.
#
# Config por conta em account.custom_attributes['ceo_digest']:
#   {
#     "enabled": true,
#     "mattermost_webhook_url": "https://mm.example.com/hooks/xxxxx",
#     "mattermost_channel": "#executivo"   # opcional
#   }
#
# Fallback global via ENV (caso a conta não tenha config própria):
#   CEO_DIGEST_MATTERMOST_WEBHOOK_URL
class Captain::Reports::CeoDigestJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform(account_id = nil, period_start = nil, period_end = nil)
    period_end = (period_end || Date.yesterday).to_date
    period_start = (period_start || (period_end - 6.days)).to_date

    scope = account_id ? Account.where(id: account_id) : Account.all
    scope.find_each { |account| deliver_for(account, period_start, period_end) }
  end

  private

  def deliver_for(account, period_start, period_end)
    config = digest_config(account)
    return log_skip(account, 'no webhook_url configured') if config[:webhook_url].blank?
    return log_skip(account, 'disabled in custom_attributes') if config[:enabled] == false

    digest = build_digest(account, period_start, period_end)
    result = deliver_to_mattermost(digest, config)
    log_result(account, result)
  rescue StandardError => e
    Rails.logger.error "[CeoDigest] unexpected error for account ##{account.id}: #{e.class} #{e.message}"
  end

  def build_digest(account, period_start, period_end)
    Captain::Reports::CeoDigestService.new(
      account: account, period_start: period_start, period_end: period_end
    ).call
  end

  def deliver_to_mattermost(digest, config)
    Captain::Reports::MattermostDeliveryService.new(
      digest: digest, webhook_url: config[:webhook_url], channel: config[:channel]
    ).call
  end

  def log_result(account, result)
    if result[:success]
      Rails.logger.info "[CeoDigest] delivered for account ##{account.id}"
    else
      Rails.logger.error "[CeoDigest] failed for account ##{account.id}: #{result.inspect}"
    end
  end

  def digest_config(account)
    raw = account.custom_attributes&.dig('ceo_digest') || {}

    {
      enabled: raw.fetch('enabled', true),
      webhook_url: raw['mattermost_webhook_url'].presence || ENV.fetch('CEO_DIGEST_MATTERMOST_WEBHOOK_URL', nil),
      channel: raw['mattermost_channel'].presence
    }
  end

  def log_skip(account, reason)
    Rails.logger.info "[CeoDigest] skipping account ##{account.id}: #{reason}"
  end
end
