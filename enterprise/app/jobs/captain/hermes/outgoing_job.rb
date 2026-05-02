# Dispara o webhook do Hermes Agent assincronamente quando uma mensagem
# do cliente chega numa inbox marcada como Hermes-enabled.
#
# Acionado pelo Enterprise::MessageTemplates::HookExecutionService no lugar do
# Captain::Conversation::ResponseBuilderJob padrão, quando
# Captain::Hermes.enabled_for?(inbox) retorna true.
class Captain::Hermes::OutgoingJob < ApplicationJob
  queue_as :default

  retry_on Captain::Hermes::Client::DispatchError, attempts: 3, wait: 5.seconds

  def perform(conversation_id, message_id)
    conversation = Conversation.find_by(id: conversation_id)
    message = Message.find_by(id: message_id)
    return if conversation.blank? || message.blank?
    return unless Captain::Hermes.enabled_for?(conversation.inbox)

    # Auto-react ANTES do dispatch — gesto chega <1s sem esperar Codex.
    # Não bloqueia fluxo: se falhar, dispatch normal continua.
    Captain::Hermes::AutoReactService.maybe_react!(message)

    # Debounce: agrupa msgs incoming desde a última resposta real do
    # agente. Quando inbox.typing_delay>0, schedule_hermes_response
    # cancela jobs pendentes e enfileira só o último — aqui pegamos o
    # texto agrupado pra Hermes ver o pensamento completo do cliente.
    combined = combined_incoming_content(conversation, message)

    Captain::Hermes::Client.new(conversation.inbox).dispatch(
      message: message, conversation: conversation, content_override: combined
    )
  end

  private

  # Concatena texto de todas as msgs incoming entre a última resposta real
  # (não-reaction) do agente e a msg âncora. Retorna nil se só tem 1 msg
  # (pra dispatch usar message.content normal).
  def combined_incoming_content(conversation, anchor_message)
    last_real_outgoing = conversation.messages
                                     .where(message_type: :outgoing)
                                     .where("(content_attributes ->> 'is_reaction') IS NULL OR (content_attributes ->> 'is_reaction') != 'true'")
                                     .order(created_at: :desc)
                                     .first

    scope = conversation.messages.where(message_type: :incoming).where('created_at <= ?', anchor_message.created_at)
    scope = scope.where('created_at > ?', last_real_outgoing.created_at) if last_real_outgoing

    texts = scope.order(:created_at).pluck(:content).map(&:to_s).reject(&:blank?).uniq
    return nil if texts.size <= 1

    Rails.logger.info("[Captain::Hermes::Debounce] agrupando #{texts.size} msgs do cliente em conv #{conversation.id}")
    texts.join("\n")
  end
end
