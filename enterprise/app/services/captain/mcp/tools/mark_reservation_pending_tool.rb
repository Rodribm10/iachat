# Tool MCP: marca reserva PIX manual como PENDENTE de revisão humana.
#
# Caso de uso: fluxo PIX manual (Padova, Express AL). Comprovante foi
# validado pela tool verificar_comprovante_pix com verdict='duvida' OU
# Hermes/atendente julgou necessário escalar mesmo com ok. NÃO confirma
# a reserva — humano precisa olhar o comprovante e decidir.
#
# Efeitos:
#   - PixCharge.status='pending_review' + persiste motivo
#   - Conversa ganha labels: revisao_humana_pix + comprovante_recebido
#   - NÃO chama ConfirmationService (cliente NÃO recebe mensagem de
#     confirmação automática até humano resolver)
class Captain::Mcp::Tools::MarkReservationPendingTool < Captain::Mcp::Tools::BaseTool
  class << self
    def name
      'marcar_reserva_pendente'
    end

    def description
      'Marca PIX manual como PENDENTE de revisão humana. Use quando verificar_comprovante_pix ' \
        "retornar verdict='duvida' (valor não bate, data antiga, beneficiário diferente, suspeitas " \
        'na imagem). NÃO confirma a reserva — humano precisa olhar antes. Cliente NÃO recebe ' \
        'mensagem automática de confirmação.'
    end

    def input_schema
      {
        type: 'object',
        properties: {
          pix_charge_id: {
            type: 'integer',
            description: 'ID da Captain::PixCharge (provider=manual). Obrigatório.'
          },
          motivo: {
            type: 'string',
            description: 'Motivo curto (uma linha) pra deixar claro pro humano o que deu errado. ' \
                         'Ex: "valor R$ 10 a menos", "comprovante de ontem", "beneficiário não bate".'
          }
        },
        required: %w[pix_charge_id motivo]
      }
    end
  end

  def call(args, _context:)
    charge = Captain::PixCharge.find_by(id: args['pix_charge_id'])
    return error_response('PixCharge não encontrada.') if charge.blank?
    return error_response("PixCharge ##{charge.id} não é manual.") unless charge.manual?

    motivo = args['motivo'].to_s.strip
    return error_response('Motivo é obrigatório.') if motivo.blank?

    mark_charge_pending!(charge, motivo)
    label_pending_review(charge.reservation&.conversation)

    text_response(
      "PIX manual ##{charge.id} marcado como pendente de revisão. Motivo: #{motivo}. " \
      "Reserva ##{charge.reservation_id} aguarda humano. Cliente NÃO foi notificado automaticamente."
    )
  rescue StandardError => e
    Rails.logger.error("[Captain::Mcp::MarkReservationPendingTool] error: #{e.class}: #{e.message}")
    error_response("Erro ao marcar reserva pendente: #{e.message}")
  end

  private

  def mark_charge_pending!(charge, motivo)
    charge.update!(
      status: 'pending_review',
      manual_review_reason: motivo
    )
  end

  def label_pending_review(conversation)
    return if conversation.blank?

    current = conversation.label_list
    merged = (current + %w[revisao_humana_pix comprovante_recebido]).uniq - %w[pagamento_confirmado reserva_feita]
    conversation.update_labels(merged)
  rescue StandardError => e
    Rails.logger.warn("[Captain::Mcp::MarkReservationPendingTool] label failed: #{e.class} - #{e.message}")
  end
end
