# Tool MCP: cria nota interna (privada) numa conversa.
#
# Caso de uso primário: fluxo PIX manual — após verificar_comprovante_pix,
# Hermes registra análise pra humano via nota interna antes de
# confirmar/marcar pendente. Genérica e reaproveitável: qualquer fluxo
# Hermes pode publicar nota interna pra deixar trilha pro time humano.
#
# Visibilidade: a nota é private=true (só atendentes veem; cliente não).
class Captain::Mcp::Tools::CreateInternalNoteTool < Captain::Mcp::Tools::BaseTool
  class << self
    def name
      'criar_nota_interna'
    end

    def description
      'Cria nota interna (privada) na conversa. Use pra registrar análise/contexto pro time humano ' \
        'sem mandar mensagem visível pro cliente. Use sempre antes de handoffs importantes ou pra logar ' \
        'verificações automáticas (ex: validação de comprovante PIX manual).'
    end

    def input_schema
      {
        type: 'object',
        properties: {
          conversation_id: {
            type: 'integer',
            description: 'ID interno da conversa (cid do [ctx]). Obrigatório.'
          },
          content: {
            type: 'string',
            description: 'Conteúdo da nota. Pode ter markdown simples (negrito, listas, quebras de linha).'
          }
        },
        required: %w[conversation_id content]
      }
    end
  end

  def call(args, context:)
    conversation = resolve_conversation(args, context)
    return error_response('Conversa não encontrada. Passe conversation_id (cid do [ctx]).') if conversation.blank?

    content = args['content'].to_s.strip
    return error_response('Conteúdo da nota vazio.') if content.blank?

    Messages::MessageBuilder.new(
      nil,
      conversation,
      { content: content, message_type: 'outgoing', private: true }
    ).perform

    text_response("Nota interna criada na conversa ##{conversation.display_id}.")
  rescue StandardError => e
    Rails.logger.error("[Captain::Mcp::CreateInternalNoteTool] error: #{e.class}: #{e.message}")
    error_response("Erro ao criar nota interna: #{e.message}")
  end

  private

  def resolve_conversation(args, context)
    conv_id = args['conversation_id'].presence ||
              context[:conversation_internal_id] ||
              context[:conversation_id]
    return nil if conv_id.blank?

    Conversation.find_by(id: conv_id) || Conversation.find_by(display_id: conv_id)
  end
end
