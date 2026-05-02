# Dispara o webhook do Hermes Agent assincronamente quando uma mensagem
# do cliente chega numa inbox marcada como Hermes-enabled.
#
# Acionado pelo Enterprise::MessageTemplates::HookExecutionService no lugar do
# Captain::Conversation::ResponseBuilderJob padrão, quando
# Captain::Hermes.enabled_for?(inbox) retorna true.
class Captain::Hermes::OutgoingJob < ApplicationJob
  queue_as :default

  retry_on Captain::Hermes::Client::DispatchError, attempts: 3, wait: 5.seconds

  HUMAN_TRIAGE_LABELS = %w[triagem_humana hermes_placeholder].freeze

  def perform(conversation_id, message_id)
    conversation = Conversation.find_by(id: conversation_id)
    message = Message.find_by(id: message_id)
    return if conversation.blank? || message.blank?
    return unless Captain::Hermes.enabled_for?(conversation.inbox)

    # Conv marcada pra triagem humana = Hermes não responde mais (até admin
    # remover label). Evita gastar token e gerar loop em msgs claramente fora
    # de escopo (operadora telefonia, banco, suporte de outro app, etc).
    if conversation.label_list.intersect?(HUMAN_TRIAGE_LABELS)
      Rails.logger.info("[Captain::Hermes::OutgoingJob] conv #{conversation.display_id} em triagem humana — pulando dispatch")
      return
    end

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
  #
  # Atenção: usa `reorder` em vez de `order` porque o model Message tem
  # default_scope `order(created_at: :asc)` — sem reorder, a SQL final fica
  # `ORDER BY created_at ASC, created_at DESC` e o ASC ganha. Resultado:
  # last_real_outgoing virava a MAIS ANTIGA, agrupando msgs de turns
  # passados (caso real: Hermes recebia "wifi+pet" colado mesmo em turns
  # separados — visto em conv 6064 em 2026-05-02).
  def combined_incoming_content(conversation, anchor_message)
    last_real_outgoing = conversation.messages
                                     .where(message_type: :outgoing)
                                     .where("(content_attributes ->> 'is_reaction') IS NULL OR (content_attributes ->> 'is_reaction') != 'true'")
                                     .reorder(created_at: :desc)
                                     .first

    scope = conversation.messages.where(message_type: :incoming).where('created_at <= ?', anchor_message.created_at)
    scope = scope.where('created_at > ?', last_real_outgoing.created_at) if last_real_outgoing

    texts = scope.reorder(created_at: :asc).pluck(:content).map(&:to_s).reject(&:blank?).uniq
    return nil if texts.size <= 1

    Rails.logger.info("[Captain::Hermes::Debounce] agrupando #{texts.size} msgs do cliente em conv #{conversation.id}")
    texts.join("\n")
  end
end
