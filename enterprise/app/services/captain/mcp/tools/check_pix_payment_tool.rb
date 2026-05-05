# Tool MCP: consulta status de pagamento Pix de uma reserva.
#
# Caso de uso: cliente diz "já paguei", "tá caindo?", "confirma aí". Tool
# consulta a cobrança mais recente da conversa diretamente no Banco Inter
# via Captain::Inter::CobStatusService. Se confirmado pago, atualiza
# Captain::PixCharge + Captain::Reservation + dispara
# Captain::Payments::ConfirmationService (que cuida de marcar reserva
# confirmada, postar mensagem de confirmação, mover labels, etc).
#
# Idempotente: chamadas repetidas com Pix já pago retornam mesmo resultado
# sem efeito colateral. Cliente pode perguntar várias vezes que tá tudo bem.
# rubocop:disable Metrics/MethodLength, Metrics/AbcSize, Layout/LineLength
class Captain::Mcp::Tools::CheckPixPaymentTool < Captain::Mcp::Tools::BaseTool
  class << self
    def name
      'check_pix_payment'
    end

    def description
      'Verifica se o Pix da reserva já foi pago no Banco Inter. Use quando o cliente ' \
        'avisar que pagou ou perguntar status. Retorna: já pago / ainda pendente / não há cobrança. ' \
        'Quando confirmar pago, dispara internamente confirmação da reserva (mensagem de ' \
        'confirmação vai pro cliente automaticamente).'
    end

    def input_schema
      {
        type: 'object',
        properties: {
          conversation_id: {
            type: 'integer',
            description: 'ID interno da conversa (cid do [ctx]). Obrigatório.'
          },
          txid: {
            type: 'string',
            description: 'Opcional. TXID específico da cobrança. Se vazio, pega a Pix mais recente da conversa.'
          }
        },
        required: ['conversation_id']
      }
    end
  end

  def call(args, context:)
    conversation = resolve_conversation(args, context)
    return error_response('Conversa não encontrada. Passe conversation_id (cid do [ctx]).') if conversation.blank?

    charge = find_charge(conversation, args['txid'])
    return text_response('Não há cobrança Pix vinculada a esta conversa. Você pode gerar uma nova com generate_pix.') if charge.blank?

    if already_paid?(charge)
      return text_response("Pagamento já confirmado para a reserva ##{charge.reservation_id} (R$ #{format('%.2f',
                                                                                                          charge.original_value.to_f)}). Pode seguir os próximos passos.")
    end

    status_result = Captain::Inter::CobStatusService.new(charge).call

    if status_result[:paid]
      mark_charge_as_paid!(charge, status_result)
      paid_amount = status_result[:paid_value].presence || charge.original_value
      text_response("Pagamento confirmado no Inter para reserva ##{charge.reservation_id} (TXID #{charge.txid}, R$ #{format('%.2f',
                                                                                                                            paid_amount.to_f)}). Reserva atualizada.")
    else
      label = status_result[:status].presence || 'ATIVA'
      text_response(
        "Ainda não consta pago no Inter (status: #{label}). Pode levar alguns minutos pra cair — " \
        'vale aguardar e tentar de novo em 1-2 min.'
      )
    end
  rescue StandardError => e
    Rails.logger.error("[Captain::Mcp::CheckPixPaymentTool] error: #{e.class}: #{e.message}")
    error_response("Erro ao consultar pagamento: #{e.message}")
  end

  private

  def resolve_conversation(args, context)
    conv_id = args['conversation_id'].presence ||
              context[:conversation_internal_id] ||
              context[:conversation_id]
    return nil if conv_id.blank?

    Conversation.find_by(id: conv_id) || Conversation.find_by(display_id: conv_id)
  end

  def find_charge(conversation, txid)
    scope = Captain::PixCharge.joins(:reservation)
                              .where(captain_reservations: { conversation_id: conversation.id, account_id: conversation.account_id })
    scope = scope.where(txid: txid.to_s.strip) if txid.present?
    scope.order(created_at: :desc).first
  end

  def already_paid?(charge)
    charge.respond_to?(:paid?) ? charge.paid? : charge.status.to_s == 'paid' || charge.reservation&.payment_status.to_s == 'paid'
  end

  def mark_charge_as_paid!(charge, status_result)
    updates = {
      status: 'paid',
      raw_webhook_payload: status_result[:raw_payload]
    }
    updates[:e2eid] = status_result[:end_to_end_id] if charge.e2eid.blank? && status_result[:end_to_end_id].present?
    updates[:paid_at] = Time.current if charge.paid_at.blank?
    charge.update!(updates)

    reservation = charge.reservation
    return if reservation.blank? || reservation.payment_status.to_s == 'paid'

    Captain::Payments::ConfirmationService.new(
      reservation: reservation,
      source: 'mcp_check_pix_payment',
      payload: status_result[:raw_payload]
    ).perform
  end
end
# rubocop:enable Metrics/MethodLength, Metrics/AbcSize, Layout/LineLength
