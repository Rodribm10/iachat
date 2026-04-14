# frozen_string_literal: true

# Endpoint público para criação de reservas via React app externo (Reserva 1001).
# Autenticado por token estático via header X-Reserva-Token.
class Public::Api::V1::Captain::PublicReservationsController < ActionController::API
  before_action :authenticate_reserva_token!

  def create
    render json: { error: 'not_implemented' }, status: :not_implemented
  end

  def status
    render json: { error: 'not_implemented' }, status: :not_implemented
  end

  private

  def authenticate_reserva_token!
    expected = ENV.fetch('RESERVA_1001_API_TOKEN', nil)
    provided = request.headers['X-Reserva-Token']

    if expected.blank?
      Rails.logger.error('[PublicReservations] RESERVA_1001_API_TOKEN not configured')
      render json: { error: 'service_unavailable' }, status: :service_unavailable and return
    end

    return if provided.present? && ActiveSupport::SecurityUtils.secure_compare(provided, expected)

    render json: { error: 'unauthorized' }, status: :unauthorized
  end
end
