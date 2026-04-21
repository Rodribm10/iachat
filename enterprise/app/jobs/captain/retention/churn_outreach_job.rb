# frozen_string_literal: true

# Manda UMA mensagem de re-engajamento pro contato. Invocado pelo Scheduler.
# Guardas internas: checa de novo cooldown e existência de conversa/inbox
# (caso dados tenham mudado entre o enqueue e a execução).
class Captain::Retention::ChurnOutreachJob < ApplicationJob
  COOLDOWN_DAYS = 180
  DISCOUNT_PCT  = 10

  queue_as :low

  def perform(contact_id)
    contact = Contact.find_by(id: contact_id)
    return if contact.blank?

    return if within_cooldown?(contact)

    conversation = find_or_create_conversation(contact)
    return if conversation.blank?

    assistant = conversation.inbox&.captain_assistant
    return if assistant.blank?

    content = build_message(contact)
    Messages::MessageBuilder.new(assistant, conversation, {
                                   content: content,
                                   message_type: 'outgoing'
                                 }).perform

    apply_label(conversation)
    mark_contact_outreached!(contact)

    Rails.logger.info("[ChurnOutreach] sent to contact=#{contact.id} conversation=#{conversation.id}")
  rescue StandardError => e
    Rails.logger.error("[ChurnOutreach] #{e.class}: #{e.message}")
  end

  private

  def within_cooldown?(contact)
    last = contact.custom_attributes&.dig('churn_outreach_at')
    return false if last.blank?

    Time.zone.parse(last.to_s) > COOLDOWN_DAYS.days.ago
  rescue ArgumentError
    false
  end

  def find_or_create_conversation(contact)
    # Tenta pegar a última conversa do contato num inbox WhatsApp (canal típico da Jasmine).
    contact.conversations
           .joins(:inbox)
           .where(inboxes: { channel_type: 'Channel::Whatsapp' })
           .order(updated_at: :desc)
           .first
  end

  def build_message(contact)
    first_name = (contact.name.to_s.split.first.presence) || 'oi'
    last_res = Captain::Reservation.where(contact_id: contact.id, payment_status: 'paid').order(check_in_at: :desc).first
    months = compute_months_away(last_res)

    <<~MSG.strip
      Oi #{first_name}! 💛

      Fiquei com saudade — faz #{months} que você não aparece aqui com a gente.

      Se rolar de voltar, tenho uma cortesia pra te receber: #{DISCOUNT_PCT}% de desconto no próximo pernoite.

      Quer que eu reserve já pra algum dia?
    MSG
  end

  def compute_months_away(last_res)
    return 'um bom tempo' if last_res.blank? || last_res.check_in_at.blank?

    diff = ((Time.current - last_res.check_in_at) / 30.days.to_i).to_i
    case diff
    when 0..1 then 'algumas semanas'
    when 2..11 then "#{diff} meses"
    else 'mais de 1 ano'
    end
  rescue StandardError
    'um bom tempo'
  end

  def apply_label(conversation)
    current = conversation.label_list || []
    conversation.update_labels((current + ['reengajamento_churn']).uniq)
  rescue StandardError => e
    Rails.logger.warn("[ChurnOutreach] label failed: #{e.message}")
  end

  def mark_contact_outreached!(contact)
    attrs = contact.custom_attributes.to_h
    attrs['churn_outreach_at'] = Time.current.iso8601
    contact.update!(custom_attributes: attrs)
  end
end
