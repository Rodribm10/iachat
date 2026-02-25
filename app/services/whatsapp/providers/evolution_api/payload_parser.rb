class Whatsapp::Providers::EvolutionApi::PayloadParser
  attr_reader :params

  def initialize(params)
    @params = params.with_indifferent_access
  end

  def external_id
    data.dig(:key, :id) || params[:id]
  end

  def from_me?
    # WuzAPI/Baileys standard
    data.dig(:key, :fromMe) || false
  end

  def sender_phone_number
    # No fromMe=false, o remoteJid é o telefone da pessoa.
    # Ex: "message":{"key":{"remoteJid":"551199999999@s.whatsapp.net"}}
    jid = extract_jid
    return nil if jid.blank? || jid.include?('@lid')

    jid.split('@').first.split(':').first
  end

  def recipient_phone_number
    # Se a mensagem foi enviada por nós (fromMe=true), o remoteJid é o destinatário (cliente)
    jid = extract_jid
    return nil if jid.blank? || jid.include?('@lid')

    jid.split('@').first.split(':').first
  end

  def message_type
    return :ignore if ignorable_webhook_event_type?

    # Baseado na key que aparece dentro de data[:message] (padrão Baileys)
    msg = unwrap_ephemeral_message(data[:message])
    return :unknown unless msg.is_a?(Hash)

    return :text if msg[:conversation].present? || msg[:extendedTextMessage].present?
    return :image if msg[:imageMessage].present?
    return :audio if msg[:audioMessage].present?
    return :video if msg[:videoMessage].present?
    return :document if msg[:documentMessage].present? || msg[:documentWithCaptionMessage].present?
    return :sticker if msg[:stickerMessage].present?

    # Evolution pode abstrair pro topo `messageType`
    type_str = data[:messageType].to_s.downcase
    case type_str
    when 'conversation', 'extendedtextmessage' then :text
    when 'imagemessage' then :image
    when 'audiomessage' then :audio
    when 'videomessage' then :video
    when 'documentmessage' then :document
    when 'stickermessage' then :sticker
    else
      :unknown
    end
  end

  def in_reply_to_external_id
    msg = unwrap_ephemeral_message(data[:message])
    return nil unless msg.is_a?(Hash)

    [:extendedTextMessage, :imageMessage, :videoMessage, :audioMessage, :stickerMessage, :documentMessage].each do |key|
      ctx = msg.dig(key, :contextInfo)
      next if ctx.blank?

      stanza = ctx[:stanzaID] || ctx[:stanzaId]
      return stanza if stanza.present?
    end

    nil
  end

  def text_content
    msg = unwrap_ephemeral_message(data[:message])
    return nil unless msg.is_a?(Hash)

    return msg[:conversation] if msg[:conversation].present?
    return msg.dig(:extendedTextMessage, :text) if msg.dig(:extendedTextMessage, :text).present?

    [:imageMessage, :videoMessage, :documentMessage].each do |media_key|
      caption = msg.dig(media_key, :caption)
      return caption if caption.present?
    end

    nil
  end

  def attachment_params
    media_key = case message_type
                when :image then :imageMessage
                when :audio then :audioMessage
                when :video then :videoMessage
                when :document then :documentMessage
                when :sticker then :stickerMessage
                end

    return nil unless media_key

    msg = unwrap_ephemeral_message(data[:message])
    media_data = msg[media_key]
    return nil unless media_data.is_a?(Hash)

    # O formato de evolução costuma vir com `base64` já embutido
    # ou com URLs pro media local proxy
    {
      base64: data.dig(:message, :base64) || data[:base64],
      mimetype: media_data['mimetype'],
      file_name: media_data['fileName'] || "file_#{external_id}",
      media_key: media_data['mediaKey']
    }
  end

  def timestamp
    timestamp_val = data[:messageTimestamp] || params[:timestamp]
    return Time.current if timestamp_val.blank?

    # Baileys envia messageTimestamp como integer UNIX
    return Time.zone.at(timestamp_val.to_i) if timestamp_val.is_a?(Integer) || timestamp_val.to_s.match?(/^\d+$/)

    begin
      Time.zone.parse(timestamp_val.to_s)
    rescue ArgumentError
      Time.current
    end
  end

  def sender_name
    data[:pushName] || data[:pushname]
  end

  def group_message?
    jid = extract_jid
    jid&.include?('@g.us')
  end

  private

  def data
    @data ||= params[:data] || params[:messages]&.first || params
  end

  def extract_jid
    data.dig(:key, :remoteJid) || data[:remoteJid]
  end

  def ignorable_webhook_event_type?
    # Filtrar eventos que não nos importam como PRESENCE_UPDATE ou STATUS
    event_type = params[:event]
    event_type.to_s != 'messages.upsert' && event_type.to_s != 'message'
  end

  def unwrap_ephemeral_message(msg)
    return {} unless msg

    msg.key?(:ephemeralMessage) ? msg.dig(:ephemeralMessage, :message) : msg
  end
end
