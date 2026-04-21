# frozen_string_literal: true

# Endpoint público disparado pelo frontend (reserva-1001 /roleta/:token) assim que
# o prêmio é revelado. Só enfileira o job — todo o trabalho (validação, claim atômico,
# envio de msg) acontece em Captain::Roleta::NotifyRevealedJob.
class Public::Api::V1::Captain::RouletteNotificationsController < ActionController::API
  def create
    token = params[:token].to_s.strip
    if token.blank?
      render json: { error: 'token ausente' }, status: :bad_request
      return
    end

    Captain::Roleta::NotifyRevealedJob.perform_later(token)
    render json: { enqueued: true }, status: :accepted
  rescue StandardError => e
    Rails.logger.error "[RouletteNotifications] erro: #{e.class} - #{e.message}"
    render json: { error: 'Internal error' }, status: :unprocessable_entity
  end
end
