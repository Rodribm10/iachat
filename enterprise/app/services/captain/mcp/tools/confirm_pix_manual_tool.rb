# Tool MCP: confirma reserva via PIX manual (após validação de comprovante).
#
# Caso de uso: fluxo PIX manual (Padova, Express AL). Comprovante já foi
# validado pela tool verificar_comprovante_pix com verdict='ok'. Esta tool
# marca a charge como paga, persiste o payload extraído e dispara
# Captain::Payments::ConfirmationService — que cuida de marcar reserva
# paid+active, atualizar labels (pagamento_confirmado/reserva_feita),
# postar nota interna automática, disparar oferta de roleta e notificar
# Hermes proativamente. Mesmo trânsito da confirmação Inter.
#
# Pré-requisito: charge.provider='manual' E charge.manual_proof_payload
# com verdict='ok'. Tool é idempotente — chamada repetida em charge já
# paga retorna sucesso sem efeito colateral.
# rubocop:disable Metrics/MethodLength, Metrics/AbcSize
class Captain::Mcp::Tools::ConfirmPixManualTool < Captain::Mcp::Tools::BaseTool
  class << self
    def name
      'confirmar_reserva_pix_manual'
    end

    def description
      'Confirma reserva PIX manual após comprovante validado (verdict=ok). Use SOMENTE depois de ' \
        'verificar_comprovante_pix retornar ok. Marca PIX como pago e dispara o trânsito padrão de ' \
        'confirmação (mensagem ao cliente, labels, roleta). NÃO use sem ter validado comprovante antes.'
    end

    def input_schema
      {
        type: 'object',
        properties: {
          pix_charge_id: {
            type: 'integer',
            description: 'ID da Captain::PixCharge (provider=manual). Obrigatório.'
          }
        },
        required: ['pix_charge_id']
      }
    end
  end

  def call(args, _context:)
    charge = Captain::PixCharge.find_by(id: args['pix_charge_id'])
    return error_response('PixCharge não encontrada.') if charge.blank?
    return error_response("PixCharge ##{charge.id} não é manual (provider=#{charge.provider}). Use o fluxo Inter normal.") unless charge.manual?
    return text_response("PIX manual ##{charge.id} já estava confirmado (idempotente). Reserva ##{charge.reservation_id} ativa.") if charge.paid?

    payload = charge.manual_proof_payload || {}
    return error_response("PixCharge ##{charge.id} não tem comprovante validado. Chame verificar_comprovante_pix antes.") if payload.blank?

    unless payload['verdict'] == 'ok'
      return error_response("Comprovante não passou na validação (verdict=#{payload['verdict']}). Use marcar_reserva_pendente.")
    end

    reservation = charge.reservation
    return error_response('PixCharge sem reserva vinculada — não consigo confirmar.') if reservation.blank?

    mark_charge_paid!(charge, payload)
    fire_confirmation!(reservation, payload)

    text_response(
      "Reserva ##{reservation.id} confirmada via PIX manual. PIX ##{charge.id} marcado como pago. " \
      'Mensagem de confirmação será enviada ao cliente automaticamente.'
    )
  rescue StandardError => e
    Rails.logger.error("[Captain::Mcp::ConfirmPixManualTool] error: #{e.class}: #{e.message}")
    Rails.logger.error(e.backtrace.first(5).join("\n"))
    error_response("Erro ao confirmar reserva manual: #{e.message}")
  end

  private

  def mark_charge_paid!(charge, payload)
    extracted = payload['extracted'].to_h
    charge.update!(
      status: 'paid',
      paid_at: Time.current,
      e2eid: extracted['id_transacao'].presence || charge.e2eid
    )
  end

  def fire_confirmation!(reservation, payload)
    Captain::Payments::ConfirmationService.new(
      reservation: reservation,
      source: 'manual_pix_proof',
      payload: payload,
      actor: nil
    ).perform
  end
end
# rubocop:enable Metrics/MethodLength, Metrics/AbcSize
