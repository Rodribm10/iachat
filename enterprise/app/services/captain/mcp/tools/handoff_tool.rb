# Tool MCP: entrega a conversa para uma pessoa, de forma determinística.
#
# Por que existe: até aqui o único jeito de um agente Hermes transferir era
# escrever a frase-âncora "⏳ Um momento — vou verificar." e torcer para o
# callback reconhecer o texto. Se o modelo variasse a frase, ou a colocasse no
# fim de uma resposta, nada acontecia — o cliente lia que alguém ia verificar e
# ninguém era chamado. Transferência não pode depender de o LLM acertar a
# redação: vira uma chamada de ferramenta, com efeito garantido.
#
# A frase-âncora continua valendo como rede de segurança no callback.
class Captain::Mcp::Tools::HandoffTool < Captain::Mcp::Tools::BaseTool
  REASONS = %w[sem_resposta_segura pedido_do_cliente fora_do_escopo
               negociacao_ou_desconto cobranca reclamacao operacao_do_dia].freeze

  class << self
    def name
      'handoff'
    end

    def description
      'Transfere a conversa para um atendente humano e encerra sua participação. ' \
        'Use quando não souber a resposta com segurança, quando o assunto sair do seu escopo ' \
        '(negociação, desconto, cobrança, reclamação, operação do dia) ou quando o cliente pedir ' \
        'falar com uma pessoa. Depois de chamar esta tool, mande APENAS a frase curta de espera ' \
        'e não responda mais nada — quem continua é a pessoa.'
    end

    def input_schema
      {
        type: 'object',
        properties: {
          conversation_id: {
            type: 'integer',
            description: 'ID interno da conversa (cid) que aparece em [ctx: cid=N] no início da mensagem do cliente. Obrigatório.'
          },
          reason: {
            type: 'string',
            enum: REASONS,
            description: 'Motivo da transferência. Vira etiqueta e entra na nota interna que a equipe lê.'
          },
          note: {
            type: 'string',
            description: 'Opcional: uma linha de contexto pra pessoa que vai assumir (o que o cliente quer, o que já foi dito).'
          }
        },
        required: %w[conversation_id]
      }
    end
  end

  def call(args, context:)
    conversation = resolve_conversation(args, context)
    return error_response('Conversation atual não encontrada. Passe conversation_id em arguments (cid do [ctx]).') if conversation.blank?

    reason = normalize_reason(args['reason'])
    Captain::Hermes::HumanTriageService.perform(conversation: conversation, reason: reason)
    append_context_note(conversation, args['note'])

    text_response(
      "Conversa #{conversation.display_id} transferida para atendimento humano (motivo: #{reason}). " \
      'Mande apenas a frase curta de espera e não responda mais nesta conversa.'
    )
  rescue StandardError => e
    Rails.logger.error("[Captain::Mcp::HandoffTool] error: #{e.class}: #{e.message}")
    error_response("Falha ao transferir: #{e.message}. NÃO diga ao cliente que transferiu.")
  end

  private

  def normalize_reason(raw)
    reason = raw.to_s.strip
    REASONS.include?(reason) ? reason : Captain::Hermes::HumanTriageService::DEFAULT_REASON
  end

  # A nota de triagem padrão já explica o motivo. Esta é a linha extra que o
  # assistente escreve para quem vai assumir — só entra quando existe de fato.
  def append_context_note(conversation, note)
    return if note.blank?

    conversation.messages.create!(
      message_type: :outgoing,
      private: true,
      account_id: conversation.account_id,
      inbox_id: conversation.inbox_id,
      sender: conversation.inbox.captain_assistant,
      content: note.to_s.strip.truncate(600),
      content_attributes: { external_source: 'hermes_handoff_context' }
    )
  end

  def resolve_conversation(args, context)
    conv_id = args['conversation_id'].presence ||
              context[:conversation_internal_id] ||
              context[:conversation_id]
    return nil if conv_id.blank?

    Conversation.find_by(id: conv_id) || Conversation.find_by(display_id: conv_id)
  end
end
