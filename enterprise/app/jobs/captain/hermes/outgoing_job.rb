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

    if conversation.blank? || message.blank?
      Rails.logger.warn(
        "[Captain::Hermes::OutgoingJob] conversation/message not found: c=#{conversation_id} m=#{message_id}"
      )
      return
    end

    unless Captain::Hermes.enabled_for?(conversation.inbox)
      Rails.logger.info(
        "[Captain::Hermes::OutgoingJob] inbox #{conversation.inbox_id} not in CAPTAIN_HERMES_INBOX_IDS — skipping"
      )
      return
    end

    # Auto-react ANTES do dispatch — gesto chega <1s sem esperar Codex.
    # Não bloqueia fluxo: se falhar, dispatch normal continua.
    Captain::Hermes::AutoReactService.maybe_react!(message)

    Captain::Hermes::Client.new(conversation.inbox).dispatch(message: message, conversation: conversation)
  end
end
