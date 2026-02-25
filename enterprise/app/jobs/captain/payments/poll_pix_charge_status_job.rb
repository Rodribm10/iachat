class Captain::Payments::PollPixChargeStatusJob < MutexApplicationJob
  queue_as :scheduled_jobs
  retry_on LockAcquisitionError, wait: 1.second, attempts: 3

  def perform(pix_charge_id)
    charge = Captain::PixCharge.includes(:reservation, :unit).find_by(id: pix_charge_id)
    return if charge.blank?

    with_lock(lock_key(charge.id), 30.seconds) do
      process_charge(charge)
    end
  rescue LockAcquisitionError
    Rails.logger.warn("[PixPolling] lock timeout for charge #{pix_charge_id}")
  rescue StandardError => e
    Rails.logger.error("[PixPolling] failure for charge #{pix_charge_id}: #{e.class} - #{e.message}")
  end

  private

  def process_charge(charge)
    return unless eligible_for_polling?(charge)

    if charge.expired_by_time?
      expire_charge!(charge)
      return
    end

    status_result = Captain::Inter::CobStatusService.new(charge).call
    if status_result[:paid]
      mark_charge_as_paid!(charge, status_result)
    elsif charge.expired_by_time?
      expire_charge!(charge)
    else
      Rails.logger.info("[PixPolling] charge #{charge.id} still pending (inter_status=#{status_result[:status]})")
    end
  end

  def eligible_for_polling?(charge)
    reservation = charge.reservation
    unit = charge.unit
    return false unless reservation.present? && unit.present?
    return false unless charge_and_reservation_eligible?(charge, reservation)
    return false unless unit_eligible?(unit)

    true
  end

  def charge_and_reservation_eligible?(charge, reservation)
    charge.active? &&
      reservation.pending_payment? &&
      reservation.payment_status.to_s == 'pending'
  end

  def unit_eligible?(unit)
    unit.proactive_pix_polling_enabled? && unit.inter_credentials_present?
  end

  def mark_charge_as_paid!(charge, status_result)
    update_attrs = {
      status: 'paid',
      raw_webhook_payload: status_result[:raw_payload]
    }
    update_attrs[:e2eid] = status_result[:end_to_end_id] if charge.e2eid.blank? && status_result[:end_to_end_id].present?
    update_attrs[:paid_at] = Time.current if charge.paid_at.blank?
    charge.update!(update_attrs)

    reservation = charge.reservation
    return if reservation.blank? || reservation.payment_status.to_s == 'paid'

    Captain::Payments::ConfirmationService.new(
      reservation: reservation,
      source: 'inter_cob_query_polling',
      payload: status_result[:raw_payload]
    ).perform
  end

  def expire_charge!(charge)
    return if charge.expired?

    charge.update!(status: 'expired')

    conversation = charge.reservation&.conversation
    return if conversation.blank?

    labels = conversation.label_list - %w[aguardando_pagamento]
    conversation.update_labels(labels)
  end

  def lock_key(charge_id)
    "captain:pix_poll:charge:#{charge_id}"
  end
end
