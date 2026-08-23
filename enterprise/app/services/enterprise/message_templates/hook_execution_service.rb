module Enterprise::MessageTemplates::HookExecutionService
  def trigger_templates
    super
    return unless should_process_captain_response?

    # Eligibility is demand-level: every inbound customer message in a
    # Captain-connected inbox counts, including conversations a human grabbed
    # first or that arrive while the account is over its usage limit —
    # otherwise the coverage denominator only ever contains conversations
    # Captain was already about to answer.
    track_captain_eligibility
    return perform_handoff unless inbox.captain_active?

    schedule_captain_response
  end

  def should_send_greeting?
    return false if captain_handling_conversation?

    super
  end

  def should_send_out_of_office_message?
    return false if captain_handling_conversation?

    super
  end

  def should_send_email_collect?
    return false if captain_handling_conversation?

    super
  end

  private

  # Metrica de cobertura que veio do upstream: toda mensagem de cliente numa
  # inbox com Captain conta como demanda, mesmo que um humano assuma antes.
  def track_captain_eligibility
    Captain::ConversationOutcomeTracker.new(
      conversation: conversation,
      assistant: inbox.captain_assistant
    ).record_eligibility(at: message.created_at)
  end

  # O motor interno do Captain saiu em 22/08/2026 — o Hermes é o único caminho
  # de resposta. Se um assistant não estiver configurado pra Hermes, a conversa
  # vai pra humano em vez de ficar em silêncio: o cliente esperando sem ninguém
  # do outro lado é o pior desfecho possível.
  def schedule_captain_response
    return schedule_hermes_response if Captain::Hermes.enabled_for?(conversation.inbox)

    handoff_misconfigured_assistant
  end

  # Assistant sem Hermes configurado: transfere pra humano SEM falar com o
  # cliente. O `perform_handoff` (usado quando a cota do Captain estoura) manda
  # "Transferring to another agent for further assistance." — mensagem em
  # inglês, que não serve pro cliente de motel brasileiro e ainda anuncia uma
  # falha interna. Aqui o cliente não vê nada: a conversa sai de `pending`, uma
  # nota interna explica o motivo, e uma pessoa assume.
  def handoff_misconfigured_assistant
    return unless conversation.pending?

    Rails.logger.warn(
      "[Captain] conv #{conversation.display_id}: assistant sem engine Hermes — " \
      'transferindo para humano em silêncio'
    )

    conversation.messages.create!(
      message_type: :outgoing,
      private: true,
      account_id: conversation.account_id,
      inbox_id: conversation.inbox_id,
      content: '⚠️ A IA não está configurada para o Hermes nesta inbox. ' \
               'O cliente NÃO recebeu resposta automática — assumir o atendimento.',
      content_attributes: { external_source: 'captain_assistant_misconfigured' }
    )

    conversation.bot_handoff!
  end

  def schedule_hermes_response
    # Inbox roteada pro Hermes Agent (engine='hermes' no assistant ou env var legacy).
    # Usa inbox.typing_delay como buffer/debounce: se outra msg chegar antes do delay
    # vencer, cancela a anterior e reenfileira (a OutgoingJob agrupa msgs incoming
    # desde a última resposta real do Hermes ao dispatch).
    delay = conversation.inbox.typing_delay.to_i
    cancel_pending_hermes_jobs!(conversation.id) if delay.positive?

    if delay.positive?
      Captain::Hermes::OutgoingJob.set(wait: delay.seconds).perform_later(conversation.id, message.id)
    else
      Captain::Hermes::OutgoingJob.perform_later(conversation.id, message.id)
    end
  end

  def cancel_pending_hermes_jobs!(conv_id)
    require 'sidekiq/api'
    cancelled = 0
    Sidekiq::ScheduledSet.new.each do |job|
      args = begin
        job.args.first
      rescue StandardError
        {}
      end
      next unless args.is_a?(Hash) && args['job_class'] == 'Captain::Hermes::OutgoingJob'
      next unless args['arguments']&.first == conv_id

      job.delete
      cancelled += 1
    end
    Rails.logger.info("[Captain::Hermes::Debounce] cancelled #{cancelled} pending OutgoingJob for conv #{conv_id}") if cancelled.positive?
  rescue StandardError => e
    Rails.logger.warn("[Captain::Hermes::Debounce] failed to cancel pending: #{e.class} - #{e.message}")
  end

  def should_process_captain_response?
    conversation.pending? && message.incoming? && inbox.captain_assistant.present?
  end

  def perform_handoff
    Rails.logger.info("Captain limit exceeded, performing handoff mid-conversation for conversation: #{conversation.id}")
    conversation.messages.create!(
      message_type: :outgoing,
      account_id: conversation.account.id,
      inbox_id: conversation.inbox.id,
      content: 'Transferring to another agent for further assistance.'
    )
    conversation.bot_handoff!
    Captain::ConversationEvents.handed_off(
      conversation: conversation,
      assistant: inbox.captain_assistant,
      source: Captain::ConversationEvents::Sources::USAGE_LIMIT,
      reason_category: :usage_limit,
      at: Time.current
    )
    send_out_of_office_message_after_handoff
  end

  def send_out_of_office_message_after_handoff
    # Campaign conversations should never receive OOO templates — the campaign itself
    # serves as the initial outreach, and OOO would be confusing in that context.
    return if conversation.campaign.present?

    ::MessageTemplates::Template::OutOfOffice.perform_if_applicable(conversation)
  end

  def captain_handling_conversation?
    conversation.pending? && captain_assistant_configured?
  end

  def captain_assistant_configured?
    inbox.captain_assistant.present?
  end
end
