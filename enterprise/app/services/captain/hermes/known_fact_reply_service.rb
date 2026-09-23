# Fronteira deterministica antes/depois do LLM. Perguntas cujo dado ja existe
# no servidor nao dependem de skill, FAQ, memoria, tool call ou interpretacao do
# modelo. O mesmo servico e usado na entrada e no callback para impor a
# pos-condicao mesmo se um callback antigo/ruim conseguir chegar.
class Captain::Hermes::KnownFactReplyService
  def initialize(conversation:, content:)
    @conversation = conversation
    @content = content.to_s
  end

  def call
    location_reply || promotion_clarification || pricing_reply
  end

  private

  def location_reply
    Captain::Hermes::LocationFactReplyService.new(
      profile_name: assistant&.hermes_profile_name,
      content: @content
    ).call
  end

  def pricing_reply
    Captain::Hermes::PricingFactReplyService.new(conversation: @conversation, content: @content).call
  end

  def promotion_clarification
    return unless %w[site_atendente lia_anuncios].include?(assistant&.hermes_profile_name)

    normalized = ActiveSupport::Inflector.transliterate(@content.downcase)
    return unless normalized.match?(/\b(promocao|promo|desconto)\b/)
    return if Captain::Hermes::KnownFactsCatalog.profile(assistant.hermes_profile_name).fetch('locations').any? do |location|
      location.fetch('aliases').any? { |alias_name| normalized.include?(ActiveSupport::Inflector.transliterate(alias_name.downcase)) }
    end

    Captain::Hermes::KnownFactReply.new(
      kind: :promotion_clarification,
      content: 'Qual unidade você procura: QNN01, Setor O, Samambaia ou Recanto das Emas? Assim confiro a promoção correta para a data.',
      exclusive: true
    )
  end

  def assistant
    @assistant ||= @conversation.inbox.captain_assistant
  end
end
