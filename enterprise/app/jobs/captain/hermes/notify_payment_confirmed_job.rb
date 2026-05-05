# Notifica o Hermes Agent sobre confirmação de pagamento de uma reserva, pra
# que o agente mande mensagem espontânea pro cliente celebrando (sem cliente
# precisar perguntar "já caiu?").
#
# Disparado por Captain::Payments::ConfirmationService (somente quando a
# inbox da reservation está em CAPTAIN_HERMES_INBOX_IDS — coexiste com o
# fluxo Captain interno).
class Captain::Hermes::NotifyPaymentConfirmedJob < ApplicationJob
  queue_as :default

  retry_on Captain::Hermes::Client::DispatchError, attempts: 3, wait: 5.seconds

  def perform(reservation_id) # rubocop:disable Metrics/MethodLength
    reservation = Captain::Reservation.find_by(id: reservation_id)
    if reservation.blank?
      Rails.logger.warn("[Captain::Hermes::NotifyPaymentConfirmedJob] reservation #{reservation_id} not found")
      return
    end

    conversation = reservation.conversation
    if conversation.blank?
      Rails.logger.info("[Captain::Hermes::NotifyPaymentConfirmedJob] reservation #{reservation_id} has no conversation — skipping")
      return
    end

    unless Captain::Hermes.enabled_for?(conversation.inbox)
      Rails.logger.info(
        "[Captain::Hermes::NotifyPaymentConfirmedJob] inbox #{conversation.inbox_id} " \
        'not Hermes-enabled — skipping (Captain interno cuida)'
      )
      return
    end

    Captain::Hermes::Client.new(conversation.inbox).notify_event(
      conversation: conversation,
      event_type: 'payment_confirmed',
      system_message: build_system_message(reservation)
    )
  end

  private

  def build_system_message(reservation)
    deposit = reservation.metadata.to_h['deposit_amount'].to_f
    total = reservation.total_amount.to_f
    suite = reservation.suite_identifier.to_s
    check_in = reservation.check_in_at&.strftime('%d/%m/%Y às %Hh%M')

    [
      '[SISTEMA: pagamento_confirmado]',
      "Pix da reserva ##{reservation.id} acabou de cair pelo banco.",
      "Sinal R$ #{format('%.2f', deposit)} de R$ #{format('%.2f', total)} (#{suite}, check-in #{check_in}).",
      'Mande mensagem espontânea celebrando a reserva confirmada e dando próximos passos curtos. Tom íntimo, sem voltar a oferecer outras coisas.'
    ].join("\n")
  end
end
