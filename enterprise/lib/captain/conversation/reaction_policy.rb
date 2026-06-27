module Captain::Conversation::ReactionPolicy
  REACTION_SAMPLE_RATE = 20
  REACTION_SAMPLE_THRESHOLD = 7
  GREETING_PATTERNS = [
    /\boi\b/,
    /\bola\b/,
    /\bbom dia\b/,
    /\bboa tarde\b/,
    /\bboa noite\b/,
    /\be ai\b/,
    /\bhello\b/,
    /\bhi\b/,
    /\bhey\b/
  ].freeze
  GRATITUDE_PATTERNS = [
    /\bobrigad[oa]\b/,
    /\bobg\b/,
    /\bvaleu\b/,
    /\bagradeco\b/,
    /\bagradecid[oa]\b/,
    /\bthanks\b/,
    /\bthank you\b/,
    /\bthx\b/,
    /\bty\b/
  ].freeze
  FAREWELL_PATTERNS = [
    /\btchau\b/,
    /\bate mais\b/,
    /\bate logo\b/,
    /\bfalou\b/,
    /\bvaleu\b/,
    /\bbye\b/,
    /\bgoodbye\b/,
    /\bsee you\b/
  ].freeze

  ALLOWED_REACTION_EMOJIS = %w[👍 🙏 👋 😊].freeze
  # rubocop:disable Layout/LineLength
  DISALLOWED_REACTION_CONTEXT = /cpf|reserv|pix|valor|preço|preco|quanto|horario|horário|data|suite|suíte|disponivel|disponível|reclama|estorno|cancel|café|cafe|conta|divida|dívida|objeto|perdid|limpeza|manuten|recepcao|recepção|subir|levar|buscar/i
  # rubocop:enable Layout/LineLength

  private

  def should_send_reaction_for?(target_message)
    return false if @response['reaction_emoji'].blank?
    return false if target_message.blank?
    return false unless ALLOWED_REACTION_EMOJIS.include?(@response['reaction_emoji'].to_s.strip)
    return false if critical_reaction_context?(target_message.content)
    return true if greeting_farewell_or_gratitude?(target_message.content)

    false
  end

  def sampled_reaction_slot?(target_message)
    (target_message.id % REACTION_SAMPLE_RATE) < REACTION_SAMPLE_THRESHOLD
  end

  def greeting_farewell_or_gratitude?(text)
    normalized = normalize_reaction_text(text)
    GREETING_PATTERNS.any? { |pattern| normalized.match?(pattern) } ||
      FAREWELL_PATTERNS.any? { |pattern| normalized.match?(pattern) } ||
      GRATITUDE_PATTERNS.any? { |pattern| normalized.match?(pattern) }
  end

  def normalize_reaction_text(text)
    I18n.transliterate(text.to_s.downcase)
  end

  def critical_reaction_context?(text)
    normalized = normalize_reaction_text(text)
    DISALLOWED_REACTION_CONTEXT.match?(normalized)
  end

  def last_incoming_message
    @conversation.messages.where(message_type: :incoming).last
  end
end
