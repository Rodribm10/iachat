# frozen_string_literal: true

# Disparado após Captain::Payments::ConfirmationService confirmar um pagamento.
# Gera o link da Roleta da Sorte e envia a mensagem pro cliente.
class Captain::Payments::OfferRouletteJob < ApplicationJob
  queue_as :low

  def perform(reservation_id)
    reservation = Captain::Reservation.find_by(id: reservation_id)
    return if reservation.blank?

    # Só oferece roleta se pagamento realmente tá confirmado (idempotência defensiva).
    return unless reservation.payment_status.to_s == 'paid'

    result = Captain::Roleta::OfferService.new(reservation: reservation).perform

    if result[:success]
      Rails.logger.info(
        "[OfferRouletteJob] reserva=#{reservation.id} url=#{result[:url]} created=#{result[:was_created]}"
      )
    else
      Rails.logger.warn("[OfferRouletteJob] reserva=#{reservation.id} erro=#{result[:error]}")
    end
  end
end
