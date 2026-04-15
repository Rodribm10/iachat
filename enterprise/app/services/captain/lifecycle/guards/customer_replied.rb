# frozen_string_literal: true

class Captain::Lifecycle::Guards::CustomerReplied < Captain::Lifecycle::Guards::Base
  MAX_DELAY = 2.hours

  def check
    config = Captain::Lifecycle::Config.for_account(@account)
    return pass unless config.pause_on_customer_reply

    window = config.pause_on_customer_reply_within_minutes.to_i.minutes
    conversation = resolve_conversation
    return pass if conversation.blank?

    last_incoming_at = last_incoming_message_at(conversation)
    return pass if last_incoming_at.blank?

    wait_until = last_incoming_at + window
    return pass if @delivery.fire_at >= wait_until

    delay = wait_until - @delivery.fire_at
    return skip('too_stale') if delay > MAX_DELAY

    reschedule(wait_until)
  end

  private

  def last_incoming_message_at(conversation)
    conversation.messages
                .where(message_type: Message.message_types[:incoming])
                .maximum(:created_at)
  end

  def resolve_conversation
    return @delivery.conversation if @delivery.conversation.present?

    inbox_id = @delivery.inbox_id || @reservation.unit&.concierge_inbox_id
    return nil if inbox_id.blank?

    @account.conversations
            .where(contact_id: @reservation.contact_id, inbox_id: inbox_id)
            .order(last_activity_at: :desc)
            .first
  end
end
