# frozen_string_literal: true

# Endpoint público para criação de reservas via React app externo (Reserva 1001).
# Autenticado por token estático via header X-Reserva-Token.
class Public::Api::V1::Captain::PublicReservationsController < ActionController::API
  before_action :authenticate_reserva_token!

  def create # rubocop:disable Metrics/AbcSize,Metrics/MethodLength
    unit = Captain::Unit.find_by(id: params[:chatwoot_unit_id])
    return render(json: { error: 'unit_not_found' }, status: :not_found) if unit.nil?
    return render(json: { error: 'unit_has_no_inbox' }, status: :unprocessable_entity) if unit.inbox_id.blank?
    return render(json: { error: 'unit_missing_inter_credentials' }, status: :unprocessable_entity) unless unit.inter_credentials_present?

    customer = params[:customer] || {}
    return render(json: { error: 'customer_required' }, status: :unprocessable_entity) if customer[:name].blank?
    return render(json: { error: 'customer_phone_required' }, status: :unprocessable_entity) if customer[:phone].blank?

    account = unit.account
    inbox   = Inbox.find(unit.inbox_id)

    # WhatsApp inbox exige source_id com apenas digitos (padrao E.164 sem o +)
    phone_digits = customer[:phone].to_s.gsub(/\D/, '')
    return render(json: { error: 'customer_phone_invalid' }, status: :unprocessable_entity) if phone_digits.empty? || phone_digits.length > 15

    normalized_phone = "+#{phone_digits}"

    contact_inbox = ::ContactInboxWithContactBuilder.new(
      source_id: phone_digits,
      inbox: inbox,
      contact_attributes: {
        name: customer[:name],
        phone_number: normalized_phone,
        email: customer[:email].presence,
        additional_attributes: {
          cpf: customer[:cpf].presence,
          origem: 'reserva-1001'
        }.compact
      }
    ).perform

    conversation = ConversationBuilder.new(
      params: ActionController::Parameters.new(
        additional_attributes: {
          source: 'reserva-1001',
          reserva_category: params[:category],
          reserva_stay_type: params[:stay_type],
          reserva_checkin_at: params[:checkin_at]
        }
      ),
      contact_inbox: contact_inbox
    ).perform

    initial_note = build_initial_note(params)

    Messages::MessageBuilder.new(
      nil,
      conversation,
      { content: initial_note, message_type: 'outgoing', private: true }
    ).perform

    reservation = Captain::Reservation.create!(
      account: account,
      inbox: inbox,
      contact: contact_inbox.contact,
      contact_inbox: contact_inbox,
      conversation: conversation,
      unit: unit,
      suite_identifier: "#{params[:category]} · #{params[:stay_type]}",
      check_in_at: params[:checkin_at],
      check_out_at: checkout_from(params[:checkin_at], params[:stay_type]),
      status: :draft,
      payment_status: 'pending',
      total_amount: (params[:total_cents].to_i / 100.0),
      metadata: {
        origem: 'reserva-1001',
        category: params[:category],
        stay_type: params[:stay_type],
        deposit_cents: params[:deposit_cents].to_i,
        notes: params[:notes]
      }
    )

    mark_conversation_as_awaiting_payment(conversation)

    deposit_amount = (params[:deposit_cents].to_i / 100.0)
    charge = Captain::Inter::CobService.new(reservation, amount: deposit_amount).call
    reservation.update!(status: :pending_payment)

    render json: {
      reservation_id: reservation.id,
      conversation_id: conversation.id,
      pix: {
        txid: charge.txid,
        copia_e_cola: charge.pix_copia_e_cola,
        qrcode_base64: nil,
        expires_at: (Time.current + Captain::PixCharge::EXPIRATION_SECONDS.seconds).iso8601
      }
    }, status: :created
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.error("[PublicReservations] validation error: #{e.message}")
    render json: { error: 'validation_failed', details: e.record.errors.full_messages }, status: :unprocessable_entity
  rescue StandardError => e
    Rails.logger.error("[PublicReservations] unexpected error: #{e.class} - #{e.message}")
    render json: { error: 'internal_error', message: e.message }, status: :internal_server_error
  end

  def status
    reservation = Captain::Reservation.find_by(id: params[:id])
    return render(json: { error: 'not_found' }, status: :not_found) if reservation.nil?

    render json: {
      reservation_id: reservation.id,
      status: reservation.payment_status
    }
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

  # Espelha Captain::Tools::GeneratePixTool#mark_conversation_as_awaiting_payment
  # (enterprise/app/services/captain/tools/generate_pix_tool.rb:713-721)
  def mark_conversation_as_awaiting_payment(conversation)
    current = conversation.label_list
    merged = (current + ['aguardando_pagamento']).uniq
    merged -= %w[pagamento_confirmado reserva_feita]
    conversation.update_labels(merged)
  rescue StandardError => e
    Rails.logger.error("[PublicReservations] label update failed: #{e.message}")
    # Não falha a request por causa disso
  end

  def build_initial_note(payload)
    <<~NOTE.strip
      Nova reserva via reserva.1001
      Categoria: #{payload[:category]}
      Permanencia: #{payload[:stay_type]}
      Check-in: #{payload[:checkin_at]}
      Total: R$ #{format('%.2f', payload[:total_cents].to_i / 100.0)}
      Entrada (PIX 50%): R$ #{format('%.2f', payload[:deposit_cents].to_i / 100.0)}
      Observacao: #{payload[:notes].presence || '-'}
    NOTE
  end

  def checkout_from(checkin_iso, stay_type)
    checkin = Time.zone.parse(checkin_iso.to_s)
    hours = case stay_type.to_s.downcase
            when '2hrs' then 2
            when '3hrs' then 3
            when 'pernoite' then 12
            when 'diaria', 'diária' then 24
            else 4 # default: 4hrs (inclui '4hrs' e qualquer outro valor)
            end
    checkin + hours.hours
  end
end
