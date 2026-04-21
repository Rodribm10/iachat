# frozen_string_literal: true

# Serviço para confirmar pagamento de uma reserva
# Atualiza status, labels e cria nota interna
class Captain::Payments::ConfirmationService
  def initialize(reservation:, source:, payload: nil, actor: nil)
    @reservation = reservation
    @source = source.to_s
    @payload = payload
    @actor = actor
  end

  def perform
    was_already_paid = reservation.payment_status.to_s == 'paid'

    ActiveRecord::Base.transaction do
      mark_reservation_paid!
      sync_conversation_labels!
      create_internal_note_once!
    end

    enqueue_roulette_offer! unless was_already_paid

    Rails.logger.info "[PaymentConfirmation] Reserva #{@reservation.id} confirmada (#{source_label})"
  end

  private

  attr_reader :reservation, :source, :payload, :actor

  def mark_reservation_paid!
    attrs = { payment_status: :paid }
    attrs[:status] = :active if reservation.respond_to?(:active?) && !reservation.active?
    reservation.update!(attrs)
  end

  def sync_conversation_labels!
    conversation = reservation.conversation
    return if conversation.blank?

    current = conversation.label_list
    merged = (current + %w[pagamento_confirmado reserva_feita]).uniq
    merged -= %w[aguardando_pagamento comprovante_recebido pagamento_em_revisao]
    conversation.update_labels(merged)
  end

  def create_internal_note_once!
    conversation = reservation.conversation
    return if conversation.blank?
    return if confirmation_note_already_created?

    content = [
      "💰 Pagamento confirmado automaticamente (#{source_label}).",
      "📋 Reserva ##{reservation.id}",
      ("🔗 Origem: #{source}" if source.present?)
    ].compact.join("\n")

    Messages::MessageBuilder.new(actor, conversation, { content: content, private: true }).perform
    mark_note_created!
  end

  def source_label
    case source
    when 'webhook_inter_pix' then 'webhook Inter Pix'
    when 'payment_callback' then 'callback de pagamento'
    when 'inter_cob_query_polling' then 'consulta periódica no Inter'
    when 'inter_cob_query' then 'consulta manual no Inter'
    else
      'integração de pagamento'
    end
  end

  def confirmation_note_already_created?
    reservation.metadata.to_h['payment_confirmed_note_at'].present?
  end

  def mark_note_created!
    metadata = reservation.metadata.to_h
    metadata['payment_confirmed_note_at'] ||= Time.current.iso8601
    metadata['payment_confirmed_source'] ||= source
    metadata['payment_confirmed_payload'] ||= payload if payload.present?
    reservation.update_column(:metadata, metadata)
  end

  # Dispara a oferta da Roleta da Sorte após confirmação.
  # Fora da transação — roleta é side effect; se falhar, confirmação continua válida.
  def enqueue_roulette_offer!
    Captain::Payments::OfferRouletteJob.perform_later(reservation.id)
  rescue StandardError => e
    Rails.logger.warn("[PaymentConfirmation] falha ao enfileirar roleta reserva=#{reservation.id}: #{e.class} - #{e.message}")
  end
end
