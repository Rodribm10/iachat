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
  GREETING_REGEX = /\A(bom\s*dia|boa\s*tarde|boa\s*noite|oi|olá|ola|e\s*aí|hey|hi|hello)[\s.!,]*\z/i
  FAREWELL_REGEX = /\A(tchau|até\s*(mais|logo|breve)|valeu\s*flw|flw|abraço|abraços|bjs|beijos)[\s.!,]*\z/i

  # Reação "ambiente" — em msgs neutras que não bateram nenhum padrão
  # acima, rola dado e reage com emoji discreto. Cobre o gap entre
  # saudação e despedida pra agente parecer mais vivo (~1 a cada 5 msgs).
  # Filtros em ambient_eligible? evitam reagir em momentos de fluxo
  # crítico (cliente mandando dados de reserva, fazendo pergunta).
  AMBIENT_EMOJIS = %w[😊 💕 ✨ 💯 🤗].freeze
  AMBIENT_PROBABILITY = 0.20
  AMBIENT_RESERVATION_KEYWORDS = /cpf|reserv|pix|valor|preço|preco|quanto|hor[áa]rio|dia\b|data\b|categori|suite|quart|chal[ée]/i

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
                 .where("content_attributes ->> 'external_source' = ?", 'hermes_auto_react')
                 .exists?(["(content_attributes ->> 'in_reply_to')::int = ?", @message.id])
  end

  def decide_emoji
    text = @message.content.to_s.strip

    return image_emoji if image_attachment?
    return audio_emoji if audio_attachment? && text.length < 10
    return '🙏' if THANKS_REGEX.match?(text)
    return '👍' if CONFIRMATION_REGEX.match?(text)
    return '👋' if GREETING_REGEX.match?(text) && first_incoming_in_conversation?
    return '❤️' if FAREWELL_REGEX.match?(text)
    return AMBIENT_EMOJIS.sample if ambient_eligible?(text) && rand < AMBIENT_PROBABILITY

    nil
  end

  # Mensagens "neutras" elegíveis pra reação ambiente: nem curtas demais
  # (provavelmente saudação que já pega regex), nem longas (geralmente
  # narrativa que pede atenção), sem ?, sem termos de fluxo de reserva
  # (preço/cpf/data — cliente está esperando ação, não emoji).
  def ambient_eligible?(text)
    return false if text.length < 6 || text.length > 180
    return false if text.include?('?')
    return false if text.match?(AMBIENT_RESERVATION_KEYWORDS)
    return false if text.match?(/\A\d/)

    true
  end

  # Saudação só reage na PRIMEIRA mensagem da conversa pra não ficar
  # forçado em conversa longa que retoma com "oi".
  def first_incoming_in_conversation?
    @conversation.messages
                 .where(message_type: :incoming)
                 .where('created_at <= ?', @message.created_at)
                 .count <= 1
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
