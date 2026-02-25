# frozen_string_literal: true

require 'faraday'

# Configura webhook do Banco Inter para receber notificações de PIX pago
# Documentação: https://developers.inter.co/references/pix#tag/Webhook-de-Pix-Cobranca/operation/webhookPut
class Captain::Inter::WebhookSetupService
  API_BASE_URL = 'https://cdpj.partners.bancointer.com.br'
  WEBHOOK_ENDPOINT = '/pix/v2/webhook'

  def initialize(unit)
    @unit = unit
    @auth_service = Captain::Inter::AuthService.new(unit)
  end

  def call
    raise 'Chave PIX não configurada para esta unidade' if @unit.inter_pix_key.blank?

    # Monta URL do webhook (nosso endpoint)
    base_url = InstallationConfig.find_by(name: 'FRONTEND_URL')&.value.presence ||
               ENV.fetch('FRONTEND_URL', 'http://localhost:3000')

    webhook_url = "#{base_url}/api/v1/captain/webhooks/inter_pix"

    # Registra webhook no Inter
    response = connection.put(webhook_path) do |req|
      req.headers['Authorization'] = "Bearer #{@auth_service.token}"
      req.headers['Content-Type'] = 'application/json'
      req.headers['x-conta-corrente'] = @unit.inter_account_number if @unit.inter_account_number.present?
      req.body = { webhookUrl: webhook_url }.to_json
    end

    if response.status == 204
      # Sucesso - atualiza unidade
      @unit.update!(
        webhook_url: webhook_url,
        webhook_configured_at: Time.current
      )

      Rails.logger.info "[WebhookSetup] Webhook configurado para #{@unit.name}: #{webhook_url}"
      { success: true, webhook_url: webhook_url }
    else
      error_msg = "Falha ao configurar webhook: HTTP #{response.status} - #{response.body}"
      Rails.logger.error "[WebhookSetup] #{error_msg}"
      { success: false, error: error_msg }
    end
  rescue StandardError => e
    Rails.logger.error "[WebhookSetup] Erro: #{e.class} - #{e.message}"
    { success: false, error: e.message }
  end

  private

  def webhook_path
    # URL-encode da chave PIX
    encoded_key = ERB::Util.url_encode(@unit.inter_pix_key)
    "#{WEBHOOK_ENDPOINT}/#{encoded_key}"
  end

  def connection
    @connection ||= Faraday.new(url: API_BASE_URL) do |conn|
      cert_raw = @unit.inter_cert_content.presence || File.read(@unit.resolved_inter_cert_path)
      key_raw  = @unit.inter_key_content.presence  || File.read(@unit.resolved_inter_key_path)

      conn.ssl[:client_cert] = OpenSSL::X509::Certificate.new(cert_raw)
      conn.ssl[:client_key]  = OpenSSL::PKey::RSA.new(key_raw)
      conn.adapter Faraday.default_adapter
    end
  end
end
