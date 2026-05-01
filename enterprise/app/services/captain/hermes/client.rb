# Cliente HTTP que dispara mensagens do Captain pro webhook do Hermes Agent.
#
# Uso:
#   Captain::Hermes::Client.new(inbox).dispatch(message: msg, conversation: conv)
#
# Resultado: POST autenticado via HMAC-SHA256 (X-Hub-Signature-256) no endpoint
# /webhooks/<subscription_name> do Hermes. O Hermes responde 202 imediato e
# processa em background. Quando terminar, invoca o plugin captain-http-callback
# que POSTa de volta no Captain (HermesCallbackController).
class Captain::Hermes::Client
  TIMEOUT_SECONDS = 10

  class DispatchError < StandardError; end

  def initialize(inbox)
    @inbox = inbox
  end

  def dispatch(message:, conversation:)
    payload = build_payload(message: message, conversation: conversation)
    body = payload.to_json
    headers = signed_headers(body)

    Rails.logger.info "[Captain::Hermes::Client] dispatching msg #{message.id} (conv #{conversation.display_id}) → #{webhook_url}"

    response = HTTParty.post(
      webhook_url,
      body: body,
      headers: headers,
      timeout: TIMEOUT_SECONDS
    )

    return response if response.success? || response.code == 202

    raise DispatchError, "Hermes webhook returned HTTP #{response.code}: #{response.body.to_s.truncate(300)}"
  rescue HTTParty::Error, Net::ReadTimeout, Net::OpenTimeout, Errno::ECONNREFUSED => e
    raise DispatchError, "Network error contacting Hermes (#{e.class}): #{e.message}"
  end

  private

  attr_reader :inbox

  def webhook_url
    Captain::Hermes.webhook_url_for(inbox)
  end

  def build_payload(message:, conversation:)
    {
      message: message.content.to_s,
      contact_name: conversation.contact&.name,
      contact_id: conversation.contact_id,
      conversation_id: conversation.display_id,
      conversation_internal_id: conversation.id,
      inbox_id: inbox.id,
      inbox_name: inbox.name,
      account_id: inbox.account_id,
      message_id: message.id,
      timestamp: Time.current.to_i
    }
  end

  def signed_headers(body)
    headers = { 'Content-Type' => 'application/json; charset=utf-8' }

    secret = Captain::Hermes.subscription_signing_secret(inbox)
    if secret.present?
      sig = OpenSSL::HMAC.hexdigest('SHA256', secret, body)
      headers['X-Hub-Signature-256'] = "sha256=#{sig}"
    else
      Rails.logger.warn "[Captain::Hermes::Client] no signing secret for inbox #{inbox.id} — Hermes will reject"
    end

    headers
  end
end
