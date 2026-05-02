# Auto-react determinístico — dispara reaction antes do LLM processar.
#
# Por que existe: quando cliente manda "obrigado", "ok", foto, etc, ele
# espera o feedback IMEDIATO (gesto). Esperar 10-30s do LLM gerar
# resposta + decidir chamar tool é UX ruim. Captain detecta padrões
# comuns e reage <1s, em paralelo ao processamento normal.
#
# A resposta de texto continua vindo do Hermes normalmente — auto-react
# é COMPLEMENTAR, não substitui.
#
# Padrões:
#   - Agradecimento curto → 🙏
#   - Confirmação ("ok", "fechado", "perfeito", "blz") → 👍
#   - Imagem (sem texto explicativo) → 😍
#   - Áudio sem ser "diferente" (não é dúvida complexa) → 🙏
#
# Conservative: só dispara em casos CLAROS. Em dúvida, deixa pro LLM
# decidir via react_to_message tool.
class Captain::Hermes::AutoReactService
  THANKS_REGEX = /\A(obrigad[oa]|valeu|vlw|thanks|brigad[oa]|grat[oa])[\s.!,]*\z/i
  CONFIRMATION_REGEX = /\A(ok|okay|fechado|perfeit[oa]|blz|beleza|combinado|certo|ótim[oa]|legal|pode\s*ser|isso\s*mesmo)[\s.!,]*\z/i

  def self.maybe_react!(message)
    new(message).maybe_react!
  end

  def initialize(message)
    @message = message
    @conversation = message.conversation
  end

  def maybe_react!
    return unless eligible?

    emoji = decide_emoji
    return if emoji.blank?

    create_reaction!(emoji)
    Rails.logger.info("[Captain::Hermes::AutoReact] msg ##{@message.id} reagiu com #{emoji}")
  rescue StandardError => e
    Rails.logger.warn("[Captain::Hermes::AutoReact] failed for msg ##{@message&.id}: #{e.class} - #{e.message}")
  end

  private

  def eligible?
    return false if @message.blank? || @conversation.blank?
    return false unless @message.message_type == 'incoming'
    return false if @message.source_id.blank?

    true
  end

  def decide_emoji
    text = @message.content.to_s.strip

    return image_emoji if image_attachment?
    return audio_emoji if audio_attachment? && text.length < 10
    return '🙏' if THANKS_REGEX.match?(text)
    return '👍' if CONFIRMATION_REGEX.match?(text)

    nil
  end

  def image_attachment?
    @message.attachments.exists?(file_type: :image)
  end

  def audio_attachment?
    @message.attachments.exists?(file_type: :audio)
  end

  def image_emoji
    '😍'
  end

  def audio_emoji
    '🙏'
  end

  def create_reaction!(emoji)
    assistant = @conversation.inbox.captain_assistant
    @conversation.messages.create!(
      message_type: :outgoing,
      account_id: @conversation.account_id,
      inbox_id: @conversation.inbox_id,
      sender: assistant,
      content: emoji,
      content_attributes: {
        is_reaction: true,
        in_reply_to_external_id: @message.source_id,
        in_reply_to: @message.id,
        external_source: 'hermes_auto_react'
      }
    )
  end
end
