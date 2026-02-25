class Captain::Reservations::MarkerBuilder
  UI_STATUS_MAP = {
    'draft' => 'draft',
    'pending_payment' => 'pending_payment',
    'scheduled' => 'confirmed',
    'active' => 'confirmed',
    'completed' => 'confirmed',
    'cancelled' => 'cancelled'
  }.freeze

  STATUS_LABELS = {
    'draft' => 'Rascunho',
    'pending_payment' => 'Aguardando pagamento',
    'confirmed' => 'Confirmada',
    'cancelled' => 'Cancelada'
  }.freeze

  def self.hidden_payload
    {
      'visible' => false
    }
  end

  def self.ui_status(status)
    UI_STATUS_MAP[status.to_s] || 'draft'
  end

  def self.status_label(ui_status)
    STATUS_LABELS[ui_status.to_s] || STATUS_LABELS['draft']
  end

  def self.build_for_conversation(conversation)
    reservation = Captain::Reservation.where(conversation_id: conversation.id).order(updated_at: :desc).first
    build_for(reservation)
  end

  def self.build_for(reservation)
    return hidden_payload if reservation.blank?

    metadata = reservation.metadata.to_h
    deposit_amount = metadata['deposit_amount'].presence&.to_f
    amount = deposit_amount&.positive? ? deposit_amount : reservation.total_amount.to_f
    amount_kind = deposit_amount&.positive? ? 'deposit' : 'total'
    normalized_status = ui_status(reservation.status)
    pix_payload = pix_payload_for(reservation)

    {
      'visible' => true,
      'status' => normalized_status,
      'status_label' => status_label(normalized_status),
      'amount' => amount.to_f,
      'amount_kind' => amount_kind,
      'check_in_at' => reservation.check_in_at&.iso8601,
      'check_out_at' => reservation.check_out_at&.iso8601,
      'suite' => reservation.suite_identifier,
      'reservation_id' => reservation.id,
      'updated_at' => reservation.updated_at&.iso8601,
      'total_amount' => reservation.total_amount.to_f,
      'deposit_amount' => deposit_amount&.to_f,
      'payment_status' => reservation.payment_status,
      'pix_status' => pix_payload[:status],
      'pix_copy_paste' => pix_payload[:pix_copy_paste],
      'pix_reason' => pix_payload[:reason]
    }
  end

  def self.pix_payload_for(reservation)
    charge = reservation.current_pix_charge || Captain::PixCharge.where(reservation_id: reservation.id).order(created_at: :desc).first
    return { pix_copy_paste: nil, reason: 'not_generated', status: 'not_generated' } if charge.blank? && reservation.pending_payment?
    return { pix_copy_paste: nil, reason: nil, status: nil } if charge.blank?

    expired = charge.expired? || charge.expired_by_time?

    return { pix_copy_paste: nil, reason: 'expired', status: 'expired' } if reservation.pending_payment? && expired

    return { pix_copy_paste: nil, reason: 'not_generated', status: charge.status } if reservation.pending_payment? && charge.pix_copia_e_cola.blank?

    {
      pix_copy_paste: charge.pix_copia_e_cola.presence,
      reason: nil,
      status: charge.status
    }
  end
end
