module Enterprise::MessageTemplates::HookExecutionService
  def trigger_templates
    super
    return unless should_process_captain_response?
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

  # O motor interno do Captain saiu em 22/08/2026 — o Hermes é o único caminho
  # de resposta. Se um assistant não estiver configurado pra Hermes, a conversa
  # vai pra humano em vez de ficar em silêncio: o cliente esperando sem ninguém
  # do outro lado é o pior desfecho possível.
  def schedule_captain_response
    return schedule_hermes_response if Captain::Hermes.enabled_for?(conversation.inbox)

    Rails.logger.warn(
      "[Captain] conv #{conversation.display_id}: assistant sem engine Hermes — " \
      'transferindo para humano'
    )
    perform_handoff
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
    return unless conversation.pending?

    Rails.logger.info("Captain limit exceeded, performing handoff mid-conversation for conversation: #{conversation.id}")
    conversation.messages.create!(
      message_type: :outgoing,
      account_id: conversation.account.id,
      inbox_id: conversation.inbox.id,
      content: 'Transferring to another agent for further assistance.'
    )
    conversation.bot_handoff!
    send_out_of_office_message_after_handoff
  end

  def send_out_of_office_message_after_handoff
    # Campaign conversations should never receive OOO templates — the campaign itself
    # serves as the initial outreach, and OOO would be confusing in that context.
    return if conversation.campaign.present?

    ::MessageTemplates::Template::OutOfOffice.perform_if_applicable(conversation)
  end

  def captain_handling_conversation?
    conversation.pending? && inbox.respond_to?(:captain_assistant) && inbox.captain_assistant.present?
  end
end
