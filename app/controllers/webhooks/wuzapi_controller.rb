class Webhooks::WuzapiController < ApplicationController
  skip_before_action :verify_authenticity_token, raise: false
  before_action :fetch_inbox
  before_action :verify_secret

  def process_payload
    Rails.logger.info "Wuzapi Webhook Received for Inbox #{@inbox.id}: #{params.inspect}"

    Whatsapp::IncomingMessageWuzapiService.new(inbox: @inbox, params: params.to_unsafe_hash).perform

    head :ok
  rescue StandardError => e
    Rails.logger.error "Error processing Wuzapi webhook: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    head :internal_server_error
  end

  private

  def fetch_inbox
    @inbox = Inbox.find(params[:inbox_id])
  rescue ActiveRecord::RecordNotFound
    head :not_found
  end

  def verify_secret
    return if @inbox.blank?

    secret = params[:secret]
    stored_secret = @inbox.channel&.provider_config&.dig('webhook_secret')

    return unless secret.blank? || secret != stored_secret

    Rails.logger.warn "Wuzapi Webhook: Invalid secret for Inbox #{@inbox.id}"
    head :unauthorized
  end
end
