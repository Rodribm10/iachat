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
    location_reply || pricing_reply
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

  def assistant
    @assistant ||= @conversation.inbox.captain_assistant
  end
end
