# Recalcula os stats desnormalizados de retenção em um único contato.
# Enfileirado por:
# - RecalculateAllContactStatsJob (scheduler diário — processa todo contato ativo)
# - Hooks event-driven: Conversation resolvida, PixCharge atualizado (paid/expired)
#
# Idempotente: pode rodar quantas vezes quiser sem efeito colateral indevido.
class Captain::Retention::RecalculateContactStatsJob < ApplicationJob
  queue_as :low

  def perform(contact_id)
    contact = Contact.find_by(id: contact_id)
    return if contact.nil?

    interaction_stats = Captain::ContactStats::InteractionCalculatorService.new(contact: contact).call
    pix_stats = calculate_pix_stats(contact)
    days_since = days_since_last(interaction_stats[:last_interaction_at])

    # rubocop:disable Rails/SkipsModelValidations
    contact.update_columns(
      interactions_count: interaction_stats[:interactions_count],
      one_shot_consultations_count: interaction_stats[:one_shot_consultations_count],
      first_interaction_at: interaction_stats[:first_interaction_at],
      last_interaction_at: interaction_stats[:last_interaction_at],
      is_recurring: interaction_stats[:is_recurring],
      days_since_last_interaction: days_since,
      pix_generated_count: pix_stats[:pix_generated_count],
      reservations_paid_count: pix_stats[:reservations_paid_count]
    )
    # rubocop:enable Rails/SkipsModelValidations
  end

  private

  # pix_generated_count: número de PixCharge emitidas (independente de status)
  # reservations_paid_count: PixCharges com status 'paid' (reserva real)
  def calculate_pix_stats(contact)
    base = Captain::PixCharge
           .joins(:reservation)
           .where(captain_reservations: { contact_id: contact.id })

    {
      pix_generated_count: base.count,
      reservations_paid_count: base.where(status: 'paid').count
    }
  end

  def days_since_last(last_at)
    return nil if last_at.blank?

    ((Time.current - last_at) / 1.day).floor
  end
end
