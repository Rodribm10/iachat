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
  # Quanto o agente reage, por assistente: `config['auto_react_mode']`.
  #
  #   'conservative' (padrao) — so agradecimento, despedida, confirmacao curta e
  #                             a saudacao de abertura. Desenhado pro contexto de
  #                             motel, onde reagir a preco/reserva soa automatico.
  #   'frequent'              — soma interesse e elogio, aceita confirmacao dentro
  #                             de frase curta, e bloqueia so o que e realmente
  #                             delicado (cobranca, estorno, cancelamento, CPF).
  #                             Para atendimento de academia/varejo, onde o gesto
  #                             rapido faz parte do tom da casa.
  #   'off'                   — nao reage.
  MODES = %w[off conservative frequent].freeze
  DEFAULT_MODE = 'conservative'.freeze

  # No modo frequente a conversa e leve: so nao se reage ao que envolve dinheiro
  # cobrado, quebra de contrato ou dado sensivel — ali um emoji soa deboche.
  SENSITIVE_CONTEXT_REGEX = /cpf|cobran|estorno|reembols|cancel|reclama|d[ií]vida|multa|processo|advogad|procon/i

  # Interesse declarado: o gesto acompanha bem e nao substitui a resposta.
  INTEREST_REGEX = /\b(quero|vou querer|tenho interesse|me interessa|bora|partiu|fechado ent[aã]o|vamos marcar|pode marcar)\b/i
  PRAISE_REGEX = /\b(ador(ei|o)|amei|que (bom|legal|massa)|top|maravilh|show de bola|perfeito mesmo|excelente|muito bom)\b/i

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

    return nil if blocked_context?(text)
    return nil if image_attachment? || audio_attachment?
    return '👋' if GREETING_REGEX.match?(text) && first_incoming_in_conversation?
    return '🙏' if farewell?(text)
    return '🙏' if THANKS_REGEX.match?(text)
    return '👍' if CONFIRMATION_REGEX.match?(text)
    return nil if emoji_only?(text)

    frequent_emoji(text)
  end

  # Extras que so valem no modo frequente. Continuam sem reagir a pergunta:
  # pergunta merece resposta, nao gesto.
  def frequent_emoji(text)
    return nil unless mode == 'frequent'
    return nil if text.include?('?')

    return '💪' if INTEREST_REGEX.match?(text)
    return '😊' if PRAISE_REGEX.match?(text)
    return '👍' if short_acknowledgement?(text)

    nil
  end

  # "ok, entendi" / "beleza então" — confirmacao dentro de frase curta, que o
  # CONFIRMATION_REGEX (ancorado na mensagem inteira) deixa passar.
  def short_acknowledgement?(text)
    return false if text.length > 40

    normalized = ActiveSupport::Inflector.transliterate(text.downcase)
    /\b(ok|beleza|blz|entendi|certo|combinado|fechado|isso mesmo|perfeito|tranquilo)\b/.match?(normalized)
  end

  def mode
    @mode ||= begin
      configured = @conversation.inbox.captain_assistant&.config.to_h['auto_react_mode'].to_s
      MODES.include?(configured) ? configured : DEFAULT_MODE
    end
  end

  def blocked_context?(text)
    return true if mode == 'off'
    return SENSITIVE_CONTEXT_REGEX.match?(text.to_s) if mode == 'frequent'

    critical_context?(text)
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
