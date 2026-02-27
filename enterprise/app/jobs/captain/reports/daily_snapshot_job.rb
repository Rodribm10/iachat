class Captain::Reports::DailySnapshotJob < ApplicationJob
  queue_as :scheduled_jobs

  # Roda todo dia à meia-noite via Sidekiq-Cron.
  # Salva um snapshot dos dados operacionais de ontem por unidade.
  def perform
    date = Date.yesterday

    Account.find_each do |account|
      save_snapshot(account, nil, date)

      account.captain_units.find_each do |unit|
        save_snapshot(account, unit, date)
      end
    end
  end

  private

  def save_snapshot(account, unit, date)
    data = build_snapshot_data(account, unit, date)

    Captain::ReportSnapshot.find_or_create_by!(
      account_id: account.id,
      captain_unit_id: unit&.id,
      snapshot_date: date
    ) do |snap|
      snap.data = data
    end
  end

  # rubocop:disable Metrics/MethodLength
  def build_snapshot_data(account, unit, date)
    conversations = base_conversations(account, unit, date)
    reservations = base_reservations(account, unit, date)

    {
      date: date.to_s,
      unit_id: unit&.id,
      unit_name: unit&.name,
      conversations: {
        total: conversations.count,
        resolved: conversations.where(status: 'resolved').count,
        open: conversations.where(status: 'open').count,
        avg_resolution_minutes: avg_resolution(conversations)
      },
      reservations: {
        total: reservations.count,
        paid: reservations.where(status: 'paid').count,
        expired: reservations.where(status: 'expired').count,
        pending: reservations.where(status: %w[pending waiting]).count,
        total_amount_cents: reservations.where(status: 'paid').sum(:amount_cents)
      }
    }
  end
  # rubocop:enable Metrics/MethodLength

  def base_conversations(account, unit, date)
    scope = account.conversations.where(created_at: date.all_day)
    if unit
      inbox_ids = unit.inboxes.pluck(:id)
      scope = scope.where(inbox_id: inbox_ids) if inbox_ids.any?
    end
    scope
  end

  def base_reservations(account, unit, date)
    scope = begin
      account.captain_reservations.where(created_at: date.all_day)
    rescue StandardError
      account.captain_units.joins(:reservations).merge(Captain::Reservation.where(created_at: date.all_day))
    end
    scope = scope.where(captain_unit_id: unit.id) if unit
    scope
  rescue StandardError
    Captain::Reservation.none
  end

  def avg_resolution(conversations)
    resolved = conversations.where.not(first_reply_created_at: nil)
    return 0 if resolved.none?

    total_minutes = resolved.sum do |c|
      next 0 unless c.first_reply_created_at

      ((c.updated_at - c.created_at) / 60).round
    end

    (total_minutes / resolved.count).round
  end
end
