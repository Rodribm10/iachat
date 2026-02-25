class Captain::Reservations::ConversationMarkerSyncService
  def initialize(reservation: nil, conversation: nil)
    @reservation = reservation
    @conversation = conversation
  end

  def perform
    conversation = target_conversation
    return if conversation.blank?

    marker = Captain::Reservations::MarkerBuilder.build_for_conversation(conversation)
    attrs = conversation.additional_attributes.to_h.deep_dup
    attrs['reservation_marker'] = marker
    return if attrs == conversation.additional_attributes.to_h

    conversation.update!(additional_attributes: attrs)
  end

  private

  def target_conversation
    return @conversation if @conversation.present?
    return @reservation.conversation if @reservation&.conversation.present?

    Conversation.find_by(id: @reservation&.conversation_id)
  end
end
