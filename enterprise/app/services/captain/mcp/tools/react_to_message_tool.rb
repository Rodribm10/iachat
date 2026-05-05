# Tool MCP: reage com emoji em uma mensagem do cliente.
#
# Caso de uso: gestos rápidos sem texto (cliente mandou foto bonita,
# áudio agradecendo, confirmação curta, etc). É bastidor — não substitui
# resposta textual; complementa ou indica leitura.
#
# Implementação: cria Message outgoing com `content_attributes.is_reaction=true`
# e `in_reply_to_external_id=<source_id da msg alvo>`. O pipeline wuzapi
# (Whatsapp::Providers::WuzapiService#send_reaction_message) detecta esses
# atributos e dispara via API do wuzapi como react nativo do WhatsApp.
class Captain::Mcp::Tools::ReactToMessageTool < Captain::Mcp::Tools::BaseTool
  class << self
    def name
      'react_to_message'
    end

    def description
      'Reage com emoji em uma mensagem do cliente (ex: 👍 ❤️ 😍 🙏 😂 😮 😢). ' \
        'Use pra gestos curtos: cliente mandou foto bonita → 😍, agradeceu → 🙏, ' \
        'confirmou algo → 👍. NÃO substitui resposta — é complementar. Sem texto extra.'
    end

    def input_schema
      {
        type: 'object',
        properties: {
          conversation_id: {
            type: 'integer',
            description: 'ID interno da conversa (cid do [ctx]). Obrigatório.'
          },
          emoji: {
            type: 'string',
            description: 'Emoji único a reagir (ex: 👍, ❤️, 😍, 🙏, 😂, 😮, 😢).'
          },
          message_id: {
            type: 'integer',
            description: 'Opcional. ID interno da mensagem do cliente. Se vazio, reage à última mensagem incoming da conversa.'
          }
        },
        required: %w[conversation_id emoji]
      }
    end
  end

  # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
  def call(args, context:)
    conversation = resolve_conversation(args, context)
    return error_response('Conversa não encontrada. Passe conversation_id (cid do [ctx]).') if conversation.blank?

    emoji = args['emoji'].to_s.strip
    return error_response('Argumento "emoji" é obrigatório.') if emoji.blank?

    target = resolve_target_message(conversation, args['message_id'])
    return error_response('Não achei mensagem do cliente pra reagir.') if target.blank?
    if target.source_id.blank?
      return error_response("Mensagem alvo (id=#{target.id}) sem source_id — wuzapi não consegue identificar a msg no WhatsApp.")
    end

    assistant = conversation.inbox.captain_assistant
    conversation.messages.create!(
      message_type: :outgoing,
      account_id: conversation.account_id,
      inbox_id: conversation.inbox_id,
      sender: assistant,
      content: emoji,
      content_attributes: {
        is_reaction: true,
        in_reply_to_external_id: target.source_id,
        external_source: 'hermes_react_tool'
      }
    )

    text_response("Reação #{emoji} enviada na mensagem ##{target.id}.")
  rescue StandardError => e
    Rails.logger.error("[Captain::Mcp::ReactToMessageTool] error: #{e.class}: #{e.message}")
    error_response("Erro ao reagir: #{e.message}")
  end
  # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

  private

  def resolve_conversation(args, context)
    conv_id = args['conversation_id'].presence ||
              context[:conversation_internal_id] ||
              context[:conversation_id]
    return nil if conv_id.blank?

    Conversation.find_by(id: conv_id) || Conversation.find_by(display_id: conv_id)
  end

  def resolve_target_message(conversation, message_id)
    if message_id.present?
      conversation.messages.find_by(id: message_id)
    else
      conversation.messages.where(message_type: :incoming).order(created_at: :desc).first
    end
  end
end
