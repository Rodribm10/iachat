# frozen_string_literal: true

# Recebe callbacks do Banco Inter quando um PIX é pago
# Documentação: https://developers.inter.co/references/pix#tag/Webhook-de-Pix-Cobranca
class Public::Api::V1::Captain::InterWebhooksController < ActionController::API
  def create
    # Parse payload - Inter envia array direto, não objeto { pix: [...] }
    payload = JSON.parse(request.body.read)

    # Normaliza: aceita tanto array direto quanto objeto { pix: [...] }
    pix_array = payload.is_a?(Array) ? payload : payload['pix']

    if pix_array.blank?
      Rails.logger.warn '[InterWebhook] Payload sem dados PIX, ignorando'
      render json: { message: 'No PIX data' }, status: :ok
      return
    end

    # Processa primeira transação do array
    pix_data = pix_array.first
    process_pix_payment(pix_data)

    render json: { message: 'Webhook processado com sucesso' }, status: :ok
  rescue JSON::ParserError => e
    Rails.logger.error "[InterWebhook] JSON inválido: #{e.message}"
    render json: { error: 'Invalid JSON' }, status: :bad_request
  rescue StandardError => e
    Rails.logger.error "[InterWebhook] Erro ao processar: #{e.class} - #{e.message}\n#{e.backtrace.first(5).join("\n")}"
    render json: { error: 'Internal error' }, status: :unprocessable_entity
  end

  private

  def process_pix_payment(pix_data)
    txid = pix_data['txid']
    e2eid = pix_data['endToEndId']
    valor = pix_data['valor']

    Rails.logger.info "[InterWebhook] Recebido: txid=#{txid}, e2eid=#{e2eid}, valor=#{valor}"

    # Idempotência: verifica se já processamos este PIX
    existing = Captain::PixCharge.find_by(e2eid: e2eid)
    if existing
      Rails.logger.info "[InterWebhook] PIX já processado (e2eid: #{e2eid})"
      return
    end

    # Busca cobrança pelo txid
    charge = Captain::PixCharge.find_by(txid: txid)
    unless charge
      Rails.logger.warn "[InterWebhook] Cobrança não encontrada (txid: #{txid})"
      return
    end

    # Atualiza cobrança
    charge.update!(
      status: 'paid',
      e2eid: e2eid,
      paid_at: Time.current,
      raw_webhook_payload: pix_data
    )

    Rails.logger.info "[InterWebhook] PixCharge #{charge.id} marcado como pago"

    # Confirma reserva
    Captain::Payments::ConfirmationService.new(
      reservation: charge.reservation,
      source: 'webhook_inter_pix',
      payload: pix_data
    ).perform

    # Notifica chat
    notify_chat(charge.reservation)
  end

  def notify_chat(reservation)
    return unless reservation.conversation_id

    conversation = Conversation.find(reservation.conversation_id)

    conversation.messages.create!(
      content: "✅ *Pagamento confirmado!*\n\nSua reserva ##{reservation.id} está garantida. Em breve você receberá mais informações sobre sua estadia!",
      message_type: :outgoing,
      account: conversation.account,
      inbox: conversation.inbox
    )

    Rails.logger.info "[InterWebhook] Notificação enviada para conversa #{conversation.id}"
  rescue StandardError => e
    Rails.logger.error "[InterWebhook] Falha ao notificar chat: #{e.message}"
  end
end
