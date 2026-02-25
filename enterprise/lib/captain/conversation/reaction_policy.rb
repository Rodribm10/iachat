module Captain::Conversation::ReactionPolicy
  REACTION_SAMPLE_RATE = 5
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

  private

  def should_send_reaction_for?(target_message)
    return false if @response['reaction_emoji'].blank?
    return false if target_message.blank?
    return true if greeting_or_farewell?(target_message.content)

    sampled_reaction_slot?(target_message)
  end

  def sampled_reaction_slot?(target_message)
    (target_message.id % REACTION_SAMPLE_RATE).zero?
  end

  def greeting_or_farewell?(text)
    normalized = normalize_reaction_text(text)
    GREETING_PATTERNS.any? { |pattern| normalized.match?(pattern) } ||
      FAREWELL_PATTERNS.any? { |pattern| normalized.match?(pattern) }
  end

  def normalize_reaction_text(text)
    I18n.transliterate(text.to_s.downcase)
  end

  def last_incoming_message
    @conversation.messages.where(message_type: :incoming).last
  end
end
