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
          },
          conversation_id: {
            type: 'integer',
            description: 'ID interno da conversa (cid) que aparece em [ctx: cid=N] no início da mensagem do cliente. Obrigatório.'
          }
        },
        required: %w[label conversation_id]
      }
    end
  end

  def call(args, context:)
    label = args['label'].to_s.strip.downcase
    return error_response('Argumento "label" é obrigatório.') if label.blank?

    conversation = resolve_conversation(args, context)
    return error_response('Conversation atual não encontrada. Passe conversation_id em arguments (cid do [ctx]).') if conversation.blank?

    ensure_account_label!(conversation.account, label)
    conversation.add_labels([label])
    text_response("Etiqueta '#{label}' adicionada à conversa #{conversation.display_id}.")
  rescue StandardError => e
    Rails.logger.error("[Captain::Mcp::AddLabelTool] error: #{e.class}: #{e.message}")
    error_response("Falha ao adicionar etiqueta: #{e.message}")
  end

  private

  # LLM passa conversation_id em arguments (lendo do [ctx: cid=N]).
  # Context (header/body) fica como fallback caso algum dia o cliente MCP
  # passe a propagar contexto automaticamente.
  def resolve_conversation(args, context)
    conv_id = args['conversation_id'].presence ||
              context[:conversation_internal_id] ||
              context[:conversation_id]
    return nil if conv_id.blank?

    Conversation.find_by(id: conv_id) || Conversation.find_by(display_id: conv_id)
  end

  # Conversation#add_labels só salva a tag via acts_as_taggable. Pra a label
  # aparecer no sidebar/dropdown da UI do Chatwoot, ela precisa existir como
  # registro oficial em account.labels (model Label). Se não existir, criamos
  # com cor neutra — gerência pode ajustar depois pelo painel.
  def ensure_account_label!(account, title)
    return if account.labels.exists?(title: title)

    account.labels.create!(
      title: title,
      description: 'Criada automaticamente via MCP (Hermes Agent)',
      color: '#5C7CFA',
      show_on_sidebar: true
    )
  end
end
