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
# Padrões permitidos em produção hoteleira:
#   - Agradecimento/despedida → 🙏
#   - Confirmação curta ("ok", "fechado", "perfeito", "blz", "show") → 👍
#   - Saudação inicial → 👋
#
# Não há mais reação ambiente/afetiva. Coração, emoji isolado e reação em
# contexto de preço/reserva/Pix/CPF/suporte operacional passam imagem de
# automação fraca e atrapalham atendimento.
class Captain::Hermes::AutoReactService
  THANKS_REGEX = /\b(muito\s+)?(obrigad[oa]|brigad[oa]|valeu|vlw|thanks|agrade[cç]o|agradecid[oa]|gratid[aã]o)\b/i
  # rubocop:disable Layout/LineLength
  CONFIRMATION_REGEX = /\A(ok|okay|fechado|perfeit[oa]|blz|beleza|combinado|certo|certinho|[oó]tim[oa]|legal|show|maravilha|tranquilo|t[aá]\s*bom|pode\s*ser|isso\s*mesmo)[\s.!,]*\z/i
  GREETING_REGEX = /\A(bom\s*dia|boa\s*tarde|boa\s*noite|oi|olá|ola|e\s*aí|hey|hi|hello)[\s.!,]*\z/i
  FAREWELL_REGEX = /\b(tchau|at[eé]\s*(mais|logo|breve|a\s+pr[oó]xima)|falou|flw|abra[cç]os?|bjs|beijos?|boa\s+noite|bom\s+descanso|at[eé]\s+amanh[aã]|at[eé]\s+depois)\b/i
  ENDING_CONTEXT_REGEX = /\b(encerr(ar|a|amos)|finaliz(ar|a|amos)|n[aã]o\s+preciso\s+mais|era\s+s[oó]\s+isso|s[oó]\s+isso|por\s+enquanto\s+[eé]\s+s[oó]|obrigad[oa]\s+pelo\s+atendimento)\b/i
  EMOJI_ONLY_REGEX = /\A[\p{Emoji_Presentation}\p{Emoji}\uFE0F\s]+[\s.!,]*\z/
  CRITICAL_CONTEXT_REGEX = /cpf|reserv|pix|valor|preço|preco|quanto|hor[áa]rio|dia\b|data\b|categori|suite|suíte|quart|chal[ée]|dispon[ií]vel|reclama|estorno|cancel|café|cafe|conta|d[ií]vida|objeto|perdid|limpeza|manuten|recep[cç][aã]o|subir|levar|buscar/i
  # rubocop:enable Layout/LineLength

  def self.maybe_react!(message)
    new(message).maybe_react!
  end

  def initialize(message)
    @message = message
    @conversation = message.conversation
  end

  def maybe_react!
    return unless eligible?
    return if already_reacted?

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

  # Evita reaction duplicada quando OutgoingJob retentar (ex: dispatch
  # retornou 401/5xx e Sidekiq reenfileirou). Sem essa guarda, cada retry
  # cria uma reaction nova e cliente vê N emojis seguidos.
  def already_reacted?
    @conversation.messages
                 .where(message_type: :outgoing)
                 .where("#{Message.content_attribute_sql('external_source')} = ?", 'hermes_auto_react')
                 .exists?(["(#{Message.content_attribute_sql('in_reply_to')})::int = ?", @message.id])
  end

  def decide_emoji
    text = @message.content.to_s.strip

    return nil if critical_context?(text)
    return nil if image_attachment? || audio_attachment?
    return '👋' if GREETING_REGEX.match?(text) && first_incoming_in_conversation?
    return '🙏' if farewell?(text)
    return '🙏' if THANKS_REGEX.match?(text)
    return '👍' if CONFIRMATION_REGEX.match?(text)
    return nil if emoji_only?(text)

    nil
  end

  def critical_context?(text)
    CRITICAL_CONTEXT_REGEX.match?(text.to_s)
  end

  # Saudação só reage na PRIMEIRA mensagem da conversa pra não ficar
  # forçado em conversa longa que retoma com "oi".
  def first_incoming_in_conversation?
    @conversation.messages
                 .where(message_type: :incoming)
                 .where('created_at <= ?', @message.created_at)
                 .count <= 1
  end

  def farewell?(text)
    normalized = ActiveSupport::Inflector.transliterate(text.to_s.downcase)
    FAREWELL_REGEX.match?(normalized) || ENDING_CONTEXT_REGEX.match?(normalized)
  end

  def emoji_only?(text)
    text.present? && EMOJI_ONLY_REGEX.match?(text)
  end

  def image_attachment?
    @message.attachments.exists?(file_type: :image)
  end

  def audio_attachment?
    @message.attachments.exists?(file_type: :audio)
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
