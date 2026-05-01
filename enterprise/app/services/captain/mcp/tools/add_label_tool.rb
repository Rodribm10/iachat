# Tool MCP: adiciona uma etiqueta na conversation atual.
#
# Caso de uso: Hermes detecta cliente recorrente / VIP / situação especial
# e quer marcar a conversa pro time humano filtrar depois.
#
# Exemplos de uso pelo LLM:
#   - "marca como cliente_recorrente"
#   - "etiqueta como pedido_desconto"
class Captain::Mcp::Tools::AddLabelTool < Captain::Mcp::Tools::BaseTool
  class << self
    def name
      'add_label'
    end

    def description
      'Adiciona uma etiqueta (label) à conversa atual do cliente. ' \
        'Use pra marcar contexto importante: cliente_recorrente, pedido_desconto, ' \
        'reclamacao, vip, etc. A etiqueta deve ser snake_case curto.'
    end

    def input_schema
      {
        type: 'object',
        properties: {
          label: {
            type: 'string',
            description: 'Nome da etiqueta em snake_case (ex: "cliente_recorrente").'
          }
        },
        required: ['label']
      }
    end
  end

  def call(args, context:)
    label = args['label'].to_s.strip
    return error_response('Argumento "label" é obrigatório.') if label.blank?

    conversation = resolve_conversation(context)
    return error_response('Conversation atual não encontrada no contexto.') if conversation.blank?

    conversation.add_labels([label])
    text_response("Etiqueta '#{label}' adicionada à conversa #{conversation.display_id}.")
  rescue StandardError => e
    Rails.logger.error("[Captain::Mcp::AddLabelTool] error: #{e.class}: #{e.message}")
    error_response("Falha ao adicionar etiqueta: #{e.message}")
  end

  private

  def resolve_conversation(context)
    conv_id = context[:conversation_internal_id] || context[:conversation_id]
    return nil if conv_id.blank?

    Conversation.find_by(id: conv_id) || Conversation.find_by(display_id: conv_id)
  end
end
