class Whatsapp::Providers::GowaService < Whatsapp::Providers::BaseService
  # O listener entrega o NOME DO EVENTO ('conversation.typing_on'), não 'typing_on'.
  # A comparação antiga só reconhecia a forma curta, então todo evento caía no
  # valor de parada e o "digitando…" nunca aparecia no WhatsApp. Aceita as duas formas.
  #
  # Os valores 'start'/'stop' são os aceitos pelo GOWA em POST /send/chat-presence
  # (campo `action`) — confirmado empiricamente contra a API. 'composing'/'paused'
  # é dialeto wuzapi/whatsmeow e o GOWA rejeita com VALIDATION_ERROR.
  TYPING_STATE_MAP = {
    Events::Types::CONVERSATION_TYPING_ON => 'start',
    Events::Types::CONVERSATION_RECORDING => 'start',
    Events::Types::CONVERSATION_TYPING_OFF => 'stop',
    'typing_on' => 'start',
    'on' => 'start',
    'recording' => 'start',
    'typing_off' => 'stop',
    'off' => 'stop'
  }.freeze

  def send_message(phone_number, message)
    return send_reaction_message(phone_number, message) if reaction_message?(message)

    response = if message.attachments.present?
                 client.send_attachment(
                   device_id,
                   phone_number,
                   message.attachments.first,
                   caption: normalize_whatsapp_markdown(message.content),
                   reply_message_id: reply_message_id(message)
                 )
               else
                 client.send_text(device_id, phone_number, normalize_whatsapp_markdown(message.content), reply_message_id: reply_message_id(message))
               end

    message_id = response.dig('results', 'id') || response.dig('results', 'message_id')
    message_id.present? ? "GOWA:#{message_id}" : nil
  end

  def send_template(_phone_number, _template_info)
    Rails.logger.warn 'GOWA não suporta templates do WhatsApp Business.'
  end

  def sync_templates; end

  def validate_provider_config?
    client.device_status(device_id)
    true
  rescue Gowa::Client::Error, ArgumentError
    false
  end

  def toggle_typing_status(typing_status, recipient_id: nil, **_kwargs)
    action = TYPING_STATE_MAP.fetch(typing_status.to_s, 'stop')
    client.send_presence(device_id, recipient_id, action)
  rescue Gowa::Client::Error => e
    Rails.logger.warn "GOWA: não foi possível atualizar o indicador de digitação: #{e.message}"
  end

  private

  def client
    @client ||= Gowa::Client.new(
      whatsapp_channel.provider_config['gowa_base_url'],
      whatsapp_channel.gowa_username,
      whatsapp_channel.gowa_password
    )
  end

  def device_id
    whatsapp_channel.provider_config.fetch('gowa_device_id')
  end

  def reply_message_id(message)
    message.in_reply_to_external_id.to_s.delete_prefix('GOWA:').presence
  end

  def reaction_message?(message)
    message.content_attributes['is_reaction'] || message.content_attributes[:is_reaction]
  end

  # O conteudo da mensagem de reacao E o emoji, e o alvo e a mensagem respondida.
  # Sem o id do alvo nao ha o que reagir — registra e desiste, sem estourar o envio.
  def send_reaction_message(phone_number, message)
    target_id = reply_message_id(message)
    if target_id.blank?
      Rails.logger.warn "GOWA: reacao sem mensagem alvo (msg #{message.id}) — ignorada"
      return nil
    end

    response = client.send_reaction(device_id, phone_number, target_id, message.content)
    message_id = response.dig('results', 'id') || response.dig('results', 'message_id')
    message_id.present? ? "GOWA:#{message_id}" : nil
  end
end
