# frozen_string_literal: true

class Captain::Inter::CertificadosAlertJob < ApplicationJob
  queue_as :scheduled_jobs

  USERNAME = 'Captain Inter Monitor'
  ICON_EMOJI = ':warning:'
  TIMEOUT_SECONDS = 10

  def perform
    resultado = Captain::Inter::CertificadosStatusService.new.call
    logar_resumo(resultado)
    return if resultado.dig(:resumo, :alertable).to_i.zero?

    webhook_url = webhook_url_configurado
    return Rails.logger.warn('[InterCertificados] alerta pendente, mas webhook Mattermost nao configurado') if webhook_url.blank?

    enviar_mattermost(webhook_url, resultado)
  rescue StandardError => e
    Rails.logger.error("[InterCertificados] falha inesperada: #{e.class} - #{e.message}")
    raise
  end

  private

  def webhook_url_configurado
    ENV.fetch('INTER_CERTIFICATE_ALERT_WEBHOOK_URL', nil).presence ||
      ENV.fetch('CEO_DIGEST_MATTERMOST_WEBHOOK_URL', nil).presence
  end

  def logar_resumo(resultado)
    resumo = resultado[:resumo]
    Rails.logger.info(
      "[InterCertificados] total=#{resumo[:total_units]} vencidos=#{resumo[:expired]} " \
      "vence_em_breve=#{resumo[:expiring_soon]} ausentes=#{resumo[:missing]} invalidos=#{resumo[:invalid]}"
    )
  end

  def enviar_mattermost(webhook_url, resultado)
    response = HTTParty.post(
      webhook_url,
      body: payload(resultado).to_json,
      headers: { 'Content-Type' => 'application/json' },
      timeout: TIMEOUT_SECONDS
    )

    if response.success?
      Rails.logger.info('[InterCertificados] alerta enviado ao Mattermost')
    else
      Rails.logger.error("[InterCertificados] Mattermost falhou #{response.code}: #{response.body.to_s.force_encoding('UTF-8')}")
    end
  end

  def payload(resultado)
    {
      username: USERNAME,
      icon_emoji: ICON_EMOJI,
      text: texto_principal(resultado),
      attachments: anexos(resultado)
    }.compact
  end

  def texto_principal(resultado)
    resumo = resultado[:resumo]
    "*Alerta Banco Inter*: #{resumo[:expired]} certificado(s) vencido(s), " \
      "#{resumo[:expiring_soon]} vencendo em ate #{resultado[:alerta_dias]} dias, " \
      "#{resumo[:missing]} ausente(s), #{resumo[:invalid]} invalido(s)."
  end

  def anexos(resultado)
    [
      anexo_por_status(resultado, 'vencido', '#d0021b', 'Certificados vencidos'),
      anexo_por_status(resultado, 'vence_em_breve', '#f5a623', 'Certificados vencendo em breve'),
      anexo_por_status(resultado, 'ausente', '#8a8f98', 'Unidades sem certificado Inter'),
      anexo_por_status(resultado, 'invalido', '#d0021b', 'Certificados invalidos')
    ].compact
  end

  def anexo_por_status(resultado, status, color, title)
    unidades = resultado[:unidades].select { |unit| unit[:status] == status }
    return nil if unidades.blank?

    {
      color: color,
      title: title,
      text: unidades.map { |unit| linha_unidade(unit) }.join("\n")
    }
  end

  def linha_unidade(unit)
    detalhes = if unit[:not_after].present?
                 "vence em #{Time.zone.parse(unit[:not_after]).strftime('%d/%m/%Y')} (#{unit[:days_until_expiry]} dia(s))"
               elsif unit[:error_message].present?
                 "#{unit[:error_class]}: #{unit[:error_message]}"
               else
                 'sem certificado configurado'
               end

    "- ##{unit[:unit_id]} #{unit[:unit_name]} — #{detalhes}"
  end
end
