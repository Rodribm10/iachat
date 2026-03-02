class Captain::Notifications::SendNotificationService
  VARIABLES = {
    '{{guest_name}}' => ->(r) { r.contact.name.to_s },
    '{{check_in_time}}' => ->(r) { r.check_in_at.strftime('%H:%M') },
    '{{check_out_time}}' => ->(r) { r.check_out_at.strftime('%H:%M') },
    '{{suite_name}}' => ->(r) { r.suite_identifier.to_s },
    '{{unit_name}}' => ->(r) { r.unit&.name.to_s }
  }.freeze

  def initialize(reservation, template)
    @reservation = reservation
    @template = template
  end

  def perform
    return unless @reservation.conversation_id?

    rendered = render_content
    send_message(rendered)
    mark_template_sent
  rescue StandardError => e
    Rails.logger.error "[SendNotificationService] Failed for reservation #{@reservation.id}, template #{@template.id}: #{e.message}"
  end

  private

  def render_content
    content = @template.content.dup
    VARIABLES.each do |placeholder, resolver|
      content.gsub!(placeholder, resolver.call(@reservation))
    end
    content
  end

  def send_message(content)
    conversation = @reservation.conversation
    assistant = conversation.inbox&.captain_inbox&.assistant

    conversation.messages.create!(
      content: content,
      message_type: :outgoing,
      account: conversation.account,
      inbox: conversation.inbox,
      sender: assistant
    )
  end

  def mark_template_sent
    current_notified = @reservation.metadata.to_h.fetch('notified_templates', [])
    updated = (current_notified + [@template.id]).uniq
    new_metadata = @reservation.metadata.to_h.merge('notified_templates' => updated)
    @reservation.update!(metadata: new_metadata)
  end
end
