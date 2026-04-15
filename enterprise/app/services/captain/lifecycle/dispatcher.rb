class Captain::Lifecycle::Dispatcher
  GUARDS = [
    Captain::Lifecycle::Guards::ReservationActive,
    Captain::Lifecycle::Guards::OptOutLabel,
    Captain::Lifecycle::Guards::MaxPerReservation,
    Captain::Lifecycle::Guards::QuietHours,
    Captain::Lifecycle::Guards::MinInterval,
    Captain::Lifecycle::Guards::CustomerReplied
  ].freeze

  def initialize(delivery)
    @delivery = delivery
  end

  def call
    return unless @delivery.status == 'scheduled'

    return if handle_guard_result(run_guards)

    rendered = render_template
    message = send_message(rendered)
    @delivery.mark_sent!(message: message, conversation: message.conversation, rendered_body: rendered)
  rescue StandardError => e
    Rails.logger.error("[LifecycleDispatcher] delivery #{@delivery.id} failed: #{e.class} #{e.message}")
    @delivery.mark_failed!(e.message)
    raise
  end

  private

  # Returns true if the guard handled (and halted) the delivery, false to proceed
  def handle_guard_result(result)
    case result[:action]
    when :skip
      @delivery.mark_skipped!(result[:reason])
      true
    when :reschedule
      apply_reschedule(result[:fire_at])
      true
    else
      false
    end
  end

  def run_guards
    GUARDS.each do |klass|
      result = klass.new(@delivery).check
      return result if result[:action] != :pass
    end
    { action: :pass }
  end

  def apply_reschedule(new_fire_at)
    @delivery.update!(fire_at: new_fire_at)
    Captain::Lifecycle::DispatcherJob.perform_at(new_fire_at, @delivery.id)
  end

  def render_template
    ctx = Captain::Lifecycle::ContextBuilder.build(@delivery.captain_reservation)
    rule = @delivery.lifecycle_rule
    Captain::PromptRenderer.render_string(rule.message_body.to_s, ctx)
  end

  def send_message(rendered_body)
    reservation = @delivery.captain_reservation
    inbox = reservation.unit&.concierge_inbox
    raise 'Concierge inbox not configured for unit' if inbox.blank?

    conversation = find_or_create_conversation(inbox, reservation)
    merge_unit_attribute(conversation, reservation)

    rule = @delivery.lifecycle_rule
    assistant = concierge_assistant_for(inbox)
    msg = Messages::MessageBuilder.new(
      assistant, conversation,
      { content: rendered_body, message_type: 'outgoing' }
    ).perform

    dispatch_interactive_if_needed(rule, reservation)
    msg
  end

  def merge_unit_attribute(conversation, reservation)
    attrs = (conversation.custom_attributes || {}).merge(
      'current_unit_id' => reservation.captain_unit_id
    )
    conversation.update!(custom_attributes: attrs)
  end

  def find_or_create_conversation(inbox, reservation)
    contact = reservation.contact
    existing = inbox.conversations.where(contact_id: contact.id).order(last_activity_at: :desc).first
    return existing if existing.present?

    contact_inbox = ContactInbox.find_or_create_by!(contact: contact, inbox: inbox) do |ci|
      ci.source_id = contact.phone_number.to_s.gsub(/\D/, '')
    end

    ::Conversation.create!(
      account_id: inbox.account_id,
      inbox_id: inbox.id,
      contact_id: contact.id,
      contact_inbox_id: contact_inbox.id
    )
  end

  def concierge_assistant_for(inbox)
    inbox.captain_inbox&.assistant
  end

  def dispatch_interactive_if_needed(rule, reservation)
    return if rule.message_type == 'text' || rule.message_payload.blank?

    inbox = reservation.unit.concierge_inbox
    provider = inbox.channel.try(:create_messaging_service) || inbox.channel
    return unless provider.respond_to?(:send_interactive_message)

    payload = render_payload(rule.message_payload, reservation)
    provider.send_interactive_message(reservation.contact.phone_number, payload)
  end

  def render_payload(payload, reservation)
    ctx = Captain::Lifecycle::ContextBuilder.build(reservation)
    rendered = Captain::PromptRenderer.render_string(payload.to_json, ctx)
    JSON.parse(rendered)
  end
end
