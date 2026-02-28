module Whatsapp::Wuzapi::PayloadParserExtension
  def in_reply_to_external_id
    msg = unwrap_ephemeral_message(params.dig(:event, :Message))
    return nil unless msg.is_a?(Hash)

    reply_id_from_extended_text(msg) ||
      reply_id_from_media(msg) ||
      reply_id_from_document_with_caption(msg) ||
      reply_id_from_conversation(msg)
  end

  def referral_info
    msg = unwrap_ephemeral_message(params.dig(:event, :Message))
    return nil unless msg.is_a?(Hash)

    ad_reply = msg.dig(:extendedTextMessage, :contextInfo, :externalAdReply)
    ad_reply ||= msg.dig('extendedTextMessage', 'contextInfo', 'externalAdReply')

    return parse_ad_reply(ad_reply) if ad_reply.is_a?(Hash) && ad_reply.present?
    return { source_type: 'ad', source_url: nil } if business_category?

    nil
  end

  private

  def reply_id_from_extended_text(msg)
    ctx = msg.dig(:extendedTextMessage, :contextInfo)
    ctx ? (ctx[:stanzaID] || ctx[:stanzaId]) : nil
  end

  def reply_id_from_media(msg)
    [:imageMessage, :videoMessage, :audioMessage, :stickerMessage, :documentMessage].each do |key|
      ctx = msg.dig(key, :contextInfo)
      next if ctx.blank?

      stanza = ctx[:stanzaID] || ctx[:stanzaId]
      return stanza if stanza.present?
    end
    nil
  end

  def reply_id_from_document_with_caption(msg)
    ctx = msg.dig(:documentWithCaptionMessage, :message, :documentMessage, :contextInfo)
    ctx ? (ctx[:stanzaID] || ctx[:stanzaId]) : nil
  end

  def reply_id_from_conversation(msg)
    ctx = msg[:contextInfo] if msg[:conversation].present?
    ctx ? (ctx[:stanzaID] || ctx[:stanzaId]) : nil
  end

  def parse_ad_reply(ad_reply)
    {
      source_url: ad_reply['sourceUrl'] || ad_reply[:sourceUrl],
      source_id: ad_reply['sourceId'] || ad_reply[:sourceId],
      source_type: 'ad',
      ctwa_clid: ad_reply['ctwaClid'] || ad_reply[:ctwaClid],
      headline: ad_reply['title'] || ad_reply[:title],
      body: ad_reply['body'] || ad_reply[:body]
    }
  end

  def business_category?
    params.dig(:event, :Info, :Category).to_s.downcase == 'business'
  end
end
