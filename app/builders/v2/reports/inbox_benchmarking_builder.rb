class V2::Reports::InboxBenchmarkingBuilder
  include DateRangeHelper

  PAID_STATUSES = V2::Reports::ConversionFunnelBuilder::PAID_STATUSES
  IGNORED_CREATED_STATUSES = V2::Reports::ConversionFunnelBuilder::IGNORED_CREATED_STATUSES

  attr_reader :account, :params

  def initialize(account, params)
    @account = account
    @params = params
  end

  # Returns one row per inbox of the account, with leads + reservations + rate,
  # plus the brand name so the frontend can group by brand for benchmarking.
  def build
    return [] if range.blank?

    inbox_brand_lookup = build_inbox_brand_lookup

    account.inboxes.map do |inbox|
      brand_name = inbox_brand_lookup[inbox.id]

      leads_total = leads_count_by_inbox[inbox.id] || 0
      reservations_created = reservations_created_by_inbox[inbox.id] || 0
      reservations_paid = reservations_paid_by_inbox[inbox.id] || 0

      {
        inbox_id: inbox.id,
        inbox_name: inbox.name,
        brand_name: brand_name,
        leads_total: leads_total,
        reservations_created: reservations_created,
        reservations_paid: reservations_paid,
        conversion_rate: percent(reservations_paid, leads_total)
      }
    end
  end

  private

  def leads_count_by_inbox
    @leads_count_by_inbox ||= account.conversations
                                     .where(created_at: range)
                                     .group(:inbox_id)
                                     .count
  end

  def reservations_created_by_inbox
    @reservations_created_by_inbox ||= account.captain_reservations
                                              .where(created_at: range)
                                              .where.not(status: IGNORED_CREATED_STATUSES)
                                              .group(:inbox_id)
                                              .count
  end

  def reservations_paid_by_inbox
    @reservations_paid_by_inbox ||= account.captain_reservations
                                           .where(created_at: range, status: PAID_STATUSES)
                                           .group(:inbox_id)
                                           .count
  end

  # inbox_id => brand_name (or nil when there is no brand mapped for this inbox)
  def build_inbox_brand_lookup
    rows = Captain::UnitInbox
           .joins(captain_unit: :brand)
           .where(inbox_id: account.inboxes.select(:id))
           .pluck('captain_unit_inboxes.inbox_id, captain_brands.name')

    rows.to_h
  end

  def percent(numerator, denominator)
    return 0 if denominator.to_i.zero?

    (numerator.to_f / denominator * 100).round(1)
  end
end
