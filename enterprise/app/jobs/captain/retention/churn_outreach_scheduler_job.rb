# frozen_string_literal: true

# Dispara mensagem de re-engajamento pra clientes que sumiram.
# Critérios:
#  - 2+ reservas pagas no histórico
#  - Última reserva há 60+ dias
#  - Nenhum outreach nos últimos 180 dias (custom_attributes.churn_outreach_at)
# Segurança:
#  - Só dias úteis 10h–18h BRT (cron garante)
#  - Máximo 20 mensagens por account por dia
class Captain::Retention::ChurnOutreachSchedulerJob < ApplicationJob
  MIN_PAID_RESERVATIONS = 2
  DAYS_SILENT          = 60
  COOLDOWN_DAYS        = 180
  MAX_PER_ACCOUNT_DAY  = 20

  queue_as :scheduled_jobs

  def perform
    return unless within_business_hours?

    Account.find_each do |account|
      # Skip accounts without any captain assistant
      next unless Captain::Assistant.exists?(account_id: account.id)

      eligible = find_eligible_contacts(account)
      next if eligible.empty?

      already_sent_today = sent_today_count(account)
      budget = MAX_PER_ACCOUNT_DAY - already_sent_today
      next if budget <= 0

      eligible.limit(budget).each do |contact|
        Captain::Retention::ChurnOutreachJob.perform_later(contact.id)
      end
    end
  rescue StandardError => e
    Rails.logger.error("[ChurnOutreachScheduler] #{e.class}: #{e.message}")
  end

  private

  def within_business_hours?
    now = Time.current.in_time_zone('America/Sao_Paulo')
    return false if now.saturday? || now.sunday?

    (10..17).cover?(now.hour)
  end

  def find_eligible_contacts(account)
    cutoff_last_res = DAYS_SILENT.days.ago
    cutoff_outreach = COOLDOWN_DAYS.days.ago.iso8601

    # Contatos com 2+ reservas PAGAS e última reserva antes do cutoff
    contact_ids = Captain::Reservation
                  .where(account_id: account.id, payment_status: 'paid')
                  .group(:contact_id)
                  .having('COUNT(*) >= ? AND MAX(check_in_at) < ?', MIN_PAID_RESERVATIONS, cutoff_last_res)
                  .pluck(:contact_id)

    return Contact.none if contact_ids.empty?

    account.contacts
           .where(id: contact_ids)
           .where(
             "custom_attributes ->> 'churn_outreach_at' IS NULL OR custom_attributes ->> 'churn_outreach_at' < ?",
             cutoff_outreach
           )
  end

  def sent_today_count(account)
    today = Time.zone.today.iso8601
    account.contacts
           .where("custom_attributes ->> 'churn_outreach_at' >= ?", today)
           .count
  end
end
