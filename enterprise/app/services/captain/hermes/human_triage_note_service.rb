class Captain::Hermes::HumanTriageNoteService
  MAX_LAST_MESSAGE_LENGTH = 180

  pattr_initialize [:conversation!, :reason]

  def perform
    conversation.messages.create!(
      message_type: :outgoing,
      private: true,
      account_id: conversation.account_id,
      inbox_id: conversation.inbox_id,
      sender: conversation.inbox.captain_assistant,
      content: note_content,
      content_attributes: {
        external_source: 'hermes_human_triage',
        triage_reason: reason
      }
    )
  end

  private

  def note_content
    complemento = last_customer_message.present? ? " Última mensagem do cliente: \"#{last_customer_message}\"." : ''

    "🔔 Triagem humana ativa: assumir atendimento desta conversa. Motivo: #{reason_text}.#{complemento}"
  end

  def reason_text
    case reason
    when 'sem_resposta_segura'
      'a IA não tinha resposta segura para a última pergunta e pediu verificação humana'
    when 'loop_detectado'
      'a IA entrou em repetição ou não conseguiu avançar no atendimento'
    else
      'a IA pediu verificação humana'
    end
  end

  def last_customer_message
    @last_customer_message ||= conversation.messages
                                           .where(message_type: :incoming)
                                           .reorder(created_at: :desc)
                                           .limit(1)
                                           .pick(:content)
                                           .to_s
                                           .squish
                                           .truncate(MAX_LAST_MESSAGE_LENGTH, separator: ' ')
  end
end
