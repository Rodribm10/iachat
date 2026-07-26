class Captain::Hermes::ReplyContextBuilder
  def initialize(message:, conversation:)
    @message = message
    @conversation = conversation
  end

  def perform
    return nil if reply_reference.blank?

    {
      external_id: reply_to_external_id,
      message_id: reply_to_message_id,
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
      Se a resposta atual usar termos como "esse valor", "desse valor", "essa", "esse" ou "isso",
      resolva a referência usando a mensagem citada antes do restante do histórico.
      Mensagem citada (#{quoted[:sender_label]}, #{quoted[:created_at]}): #{quoted_content}
    TEXT
  end

  def missing_reply_context
    <<~TEXT.strip
      [CONTEXTO DE RESPOSTA DO WHATSAPP]
      O cliente respondeu citando uma mensagem anterior, mas o Chatwoot não encontrou o conteúdo da mensagem citada.
      Referência citada: #{reply_reference}
    TEXT
  end

  def reply_reference
    reply_to_external_id.presence || reply_to_message_id.presence
  end

  def reply_to_external_id
    @reply_to_external_id ||= message.in_reply_to_external_id.presence ||
                              message.content_attributes.to_h['in_reply_to_external_id'].presence ||
                              message.content_attributes.to_h[:in_reply_to_external_id].presence
  end

  def reply_to_message_id
    @reply_to_message_id ||= message.in_reply_to_id.presence ||
                             message.content_attributes.to_h['in_reply_to'].presence ||
                             message.content_attributes.to_h[:in_reply_to].presence
  end

  def quoted_message
    @quoted_message ||= begin
      found_by_id = conversation.messages.find_by(id: reply_to_message_id) if reply_to_message_id.present?
      found_by_id || conversation.messages.find_by(source_id: reply_to_external_id)
    end
  end

  def quoted_message_snapshot
    return nil if quoted_message.blank?

    {
      id: quoted_message.id,
      external_id: quoted_message.source_id,
      message_type: quoted_message.message_type,
      sender_label: sender_label,
      sender_name: sender_name,
      content: quoted_message_content,
      attachment_summary: attachment_summary,
      created_at: quoted_message.created_at&.iso8601
    }.compact
  end

  # `available_name` só existe em User, AgentBot e Captain::Assistant — Contact
  # não tem. Como o cliente citando a PRÓPRIA mensagem é o caso mais comum no
  # WhatsApp, `sender&.available_name` levantava NoMethodError e derrubava o
  # OutgoingJob inteiro: a mensagem nunca chegava ao Hermes e o cliente ficava
  # sem resposta. Foram 83 ocorrências até 26/07/2026.
  def sender_name
    sender = quoted_message.sender
    return nil if sender.blank?

    sender.try(:available_name).presence || sender.try(:name).presence
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
