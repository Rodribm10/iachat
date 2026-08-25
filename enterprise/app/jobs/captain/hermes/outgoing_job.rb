# Dispara o webhook do Hermes Agent assincronamente quando uma mensagem
# do cliente chega numa inbox marcada como Hermes-enabled.
#
# Acionado pelo Enterprise::MessageTemplates::HookExecutionService quando
# Captain::Hermes.enabled_for?(inbox) retorna true — que desde 22/08/2026 é o
# único caminho de resposta: o motor interno do Captain foi desligado.
class Captain::Hermes::OutgoingJob < ApplicationJob
  queue_as :default

  retry_on Captain::Hermes::Client::DispatchError, attempts: 3, wait: 5.seconds

  # Labels que a triagem humana aplica. Elas NÃO bloqueiam mais o agente —
  # servem pra filtro e relatório. Quem manda é o status (ver #perform).
  # `hermes_placeholder` ficou aqui por compatibilidade: não é aplicada em
  # lugar nenhum do código, mas pode existir em conversa antiga.
  HUMAN_TRIAGE_LABELS = %w[triagem_humana hermes_placeholder].freeze

  # Trava INTENCIONAL: alguém marcou a conversa dizendo "aqui a IA não fala".
  # É o caso dos funcionários e de contatos que o time prefere atender à mão.
  # Diferente das labels de triagem, esta vale mesmo dentro do funil da IA.
  AI_DISABLED_LABELS = %w[duda_desligada].freeze

  def perform(conversation_id, message_id)
    conversation = Conversation.find_by(id: conversation_id)
    message = Message.find_by(id: message_id)
    return if conversation.blank? || message.blank?
    return unless Captain::Hermes.enabled_for?(conversation.inbox)

    return if skip_dispatch?(conversation)

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

  # A trava é o STATUS, não a label. `pending` é o funil da IA: se a conversa
  # está lá, foi decisão de quem opera e o agente responde. Se saiu (alguém
  # assumiu entre o agendamento e a execução — o job roda com typing_delay),
  # o agente cala.
  #
  # Antes isso era decidido por label de triagem, que ficava órfã na conversa e
  # amordaçava o agente pra sempre: devolver pra IA não adiantava nada, porque
  # ninguém removia a label. Status é o que a tela mostra e o que o operador
  # controla — é a fonte de verdade certa.
  def skip_dispatch?(conversation)
    unless conversation.pending?
      log_skip(conversation, "fora do funil da IA (#{conversation.status})")
      return true
    end

    return false unless conversation.label_list.intersect?(AI_DISABLED_LABELS)

    log_skip(conversation, 'IA desligada por marcação')
    true
  end

  def log_skip(conversation, motivo)
    Rails.logger.info("[Captain::Hermes::OutgoingJob] conv #{conversation.display_id} #{motivo} — pulando dispatch")
  end

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
  def reaction_sql
    @reaction_sql ||= Message.content_attribute_sql('is_reaction')
  end

  def combined_incoming_content(conversation, anchor_message)
    last_real_outgoing = conversation.messages
                                     .where(message_type: :outgoing)
                                     .where("#{reaction_sql} IS NULL OR #{reaction_sql} != 'true'")
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
