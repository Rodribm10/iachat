class Webhooks::GowaController < ApplicationController
  skip_before_action :verify_authenticity_token, raise: false
  before_action :fetch_inbox
  before_action :verify_signature

  def process_payload
    Whatsapp::IncomingMessageGowaService.new(inbox: @inbox, params: payload).perform
    head :ok
  rescue StandardError => e
    Rails.logger.error "GOWA webhook inbox #{@inbox&.id}: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    head :internal_server_error
  end

  private

  def fetch_inbox
    @inbox = Inbox.find(params[:inbox_id])
    head :not_found unless @inbox.channel&.provider == 'gowa'
  rescue ActiveRecord::RecordNotFound
    head :not_found
  end

  def verify_signature
    return if @inbox.blank? || performed?

    signature = request.headers['X-Hub-Signature-256'].to_s.delete_prefix('sha256=')
    expected = OpenSSL::HMAC.hexdigest('SHA256', webhook_secret, request.raw_post)
    return if signature.present? && ActiveSupport::SecurityUtils.secure_compare(signature, expected)

    Rails.logger.warn "GOWA webhook com assinatura inválida para inbox #{@inbox.id}"
    head :unauthorized
  end

  def payload
    @payload ||= JSON.parse(request.raw_post)
  end

  def webhook_secret
    @inbox.channel.provider_config.fetch('webhook_secret')
  end
end
