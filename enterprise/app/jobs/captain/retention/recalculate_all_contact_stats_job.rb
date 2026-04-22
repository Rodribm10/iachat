# Scheduler diário que recalcula os stats de retenção de todos os contatos
# relevantes. Evita varrer a base inteira quando não há necessidade: só processa
# contatos que:
#   (a) receberam ou enviaram mensagem nos últimos 120 dias (cobertura normal), OU
#   (b) estão como "ativos" ou "adormecidos" hoje (last_interaction_at nos últimos
#       120 dias) — garante que a transição pra "inativo" seja capturada mesmo
#       se não houve conversa nova.
#
# Batch processado em grupo de 200 contacts por vez pra não estourar a fila.
class Captain::Retention::RecalculateAllContactStatsJob < ApplicationJob
  queue_as :scheduled_jobs

  LOOKBACK = 120.days
  BATCH_SIZE = 200

  def perform
    total = 0

    contact_ids_to_recalc.find_in_batches(batch_size: BATCH_SIZE) do |batch|
      batch.each do |contact_id|
        Captain::Retention::RecalculateContactStatsJob.perform_later(contact_id)
        total += 1
      end
    end

    Rails.logger.info "[Captain::Retention] Enqueued recalc for #{total} contacts"
  end

  private

  def contact_ids_to_recalc
    since = LOOKBACK.ago

    active_from_messages = Contact
                           .joins(conversations: :messages)
                           .where('messages.created_at >= ?', since)
                           .distinct
                           .pluck(:id)

    active_from_stats = Contact
                        .where('last_interaction_at >= ?', since)
                        .pluck(:id)

    Contact.where(id: (active_from_messages + active_from_stats).uniq).select(:id)
  end
end
