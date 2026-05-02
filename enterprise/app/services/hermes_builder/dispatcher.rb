# Encaminha mensagens da UI Hermes Builder pro gateway do Construtor (Hermes).
#
# Configuração:
#   ENV['HERMES_BUILDER_WEBHOOK_URL'] — default: http://172.17.0.1:8646/webhooks/construtor-admin
#   ENV['HERMES_BUILDER_WEBHOOK_SECRET'] — secret HMAC pra assinar payload
#
# Construtor responde async via plugin captain-http-callback que faz POST
# pra /webhooks/captain/builder_callback (HermesBuilderCallbackController).
module HermesBuilder::Dispatcher
  DEFAULT_URL = 'http://172.17.0.1:8646/webhooks/construtor-admin'.freeze
  TIMEOUT = 10

  class DispatchError < StandardError; end

  module_function

  def send_to_construtor(session_id:, message:)
    payload = { message: message, hermes_session_id: session_id }
    body = payload.to_json
    headers = signed_headers(body)

    Rails.logger.info("[HermesBuilder::Dispatcher] sending session=#{session_id} (#{message.length} chars)")

    response = HTTParty.post(webhook_url, body: body, headers: headers, timeout: TIMEOUT)
    return response if response.success? || response.code == 202

    raise DispatchError, "Construtor returned HTTP #{response.code}: #{response.body.to_s.truncate(200)}"
  rescue HTTParty::Error, Net::ReadTimeout, Net::OpenTimeout, Errno::ECONNREFUSED => e
    raise DispatchError, "Network error contacting Construtor (#{e.class}): #{e.message}"
  end

  def webhook_url
    ENV.fetch('HERMES_BUILDER_WEBHOOK_URL', DEFAULT_URL)
  end

  def signed_headers(body)
    headers = { 'Content-Type' => 'application/json; charset=utf-8' }
    secret = ENV.fetch('HERMES_BUILDER_WEBHOOK_SECRET', nil)
    if secret.present?
      sig = OpenSSL::HMAC.hexdigest('SHA256', secret, body)
      headers['X-Hub-Signature-256'] = "sha256=#{sig}"
    end
    headers
  end
end
