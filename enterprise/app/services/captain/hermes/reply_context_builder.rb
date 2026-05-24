class Captain::Hermes::ReplyContextBuilder
  def initialize(message:, conversation:)
    @message = message
    @conversation = conversation
  end

  def perform
    return nil if reply_to_external_id.blank?

    {
      external_id: reply_to_external_id,
      found: quoted_message.present?,
      quoted_message: quoted_message_snapshot
    }.compact
  end

  def wrap_message(current_text)
    return current_text if reply_context.blank?

    "#{formatted_reply_context}\n\n[RESPOSTA ATUAL DO CLIENTE]\n#{current_text}"
  end

  private

  attr_reader :message, :conversation

  def reply_context
    @reply_context ||= perform
  end

  def formatted_reply_context
    return missing_reply_context unless reply_context[:found]

    quoted = reply_context[:quoted_message]
    quoted_content = quoted[:content].presence || quoted[:attachment_summary].presence || '[mensagem sem texto]'

    <<~TEXT.strip
      [CONTEXTO DE RESPOSTA DO WHATSAPP]
      O cliente respondeu citando uma mensagem anterior.
      Interprete a resposta atual como referência direta a essa mensagem citada.
      Mensagem citada (#{quoted[:sender_label]}, #{quoted[:created_at]}): #{quoted_content}
    TEXT
  end

  def missing_reply_context
    <<~TEXT.strip
      [CONTEXTO DE RESPOSTA DO WHATSAPP]
      O cliente respondeu citando uma mensagem anterior, mas o Chatwoot não encontrou o conteúdo da mensagem citada.
      ID externo citado: #{reply_context[:external_id]}
    TEXT
  end

  def reply_to_external_id
    @reply_to_external_id ||= message.in_reply_to_external_id.presence ||
                              message.content_attributes.to_h['in_reply_to_external_id'].presence ||
                              message.content_attributes.to_h[:in_reply_to_external_id].presence
  end

  def quoted_message
    @quoted_message ||= conversation.messages.find_by(source_id: reply_to_external_id)
  end

  def quoted_message_snapshot
    return nil if quoted_message.blank?

    {
      id: quoted_message.id,
      external_id: quoted_message.source_id,
      message_type: quoted_message.message_type,
      sender_label: sender_label,
      sender_name: quoted_message.sender&.available_name,
      content: quoted_message_content,
      attachment_summary: attachment_summary,
      created_at: quoted_message.created_at&.iso8601
    }.compact
  end

  def sender_label
    return 'cliente' if quoted_message.incoming?
    return 'atendente/Hermes' if quoted_message.outgoing?

    'sistema'
  end

  def quoted_message_content
    quoted_message.content.to_s.truncate(1200)
  end

  def attachment_summary
    return nil if quoted_message.attachments.blank?

    types = quoted_message.attachments.filter_map(&:file_type)
    "anexos: #{types.join(', ')}"
  end
end
