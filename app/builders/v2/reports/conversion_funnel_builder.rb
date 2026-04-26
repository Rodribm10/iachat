class V2::Reports::ConversionFunnelBuilder
  include DateRangeHelper

  # Reservation statuses we treat as "paid" — covers PIX (Inter), payments at the
  # reception, card on arrival, etc. Anything that means the booking went through.
  PAID_STATUSES = %w[active completed confirmed].freeze

  # Statuses we ignore from "created" (drafts are pre-save, never went live)
  IGNORED_CREATED_STATUSES = %w[draft].freeze

  attr_reader :account, :params

  def initialize(account, params)
    @account = account
    @params = params
  end

  def metrics
    {
      leads: leads_breakdown,
      reservations: reservations_breakdown,
      conversion_rates: conversion_rates_breakdown
    }
  end

  private

  def filter_inbox_id
    @filter_inbox_id ||= params[:inbox_id].presence&.to_i
  end

  def conversations_in_period
    @conversations_in_period ||= begin
      scope = account.conversations.where(created_at: range)
      scope = scope.where(inbox_id: filter_inbox_id) if filter_inbox_id
      scope
    end
  end

  def reservations_in_period
    @reservations_in_period ||= begin
      scope = account.captain_reservations.where(created_at: range)
      scope = scope.where(inbox_id: filter_inbox_id) if filter_inbox_id
      scope.where.not(status: IGNORED_CREATED_STATUSES)
    end
  end

  # Leads classified using the same logic as the "Novas × Retorno" tab:
  # new = no prior conversation in any inbox of the account
  # returning = had a prior conversation
  def leads_breakdown
    total = conversations_in_period.count
    return { total: 0, new: 0, returning: 0 } if total.zero?

    conv_with_prior_ids = conversations_in_period
                          .joins('INNER JOIN conversations prev ON prev.contact_id = conversations.contact_id ' \
                                 'AND prev.account_id = conversations.account_id ' \
                                 'AND prev.id < conversations.id')
                          .distinct
                          .pluck(:id)

    returning = conv_with_prior_ids.size
    {
      total: total,
      new: total - returning,
      returning: returning
    }
  end

  def reservations_breakdown
    created = reservations_in_period.count
    paid = reservations_in_period.where(status: PAID_STATUSES).count

    {
      created: created,
      paid: paid
    }
  end

  def conversion_rates_breakdown
    leads_total = conversations_in_period.count
    reservations_paid = reservations_in_period.where(status: PAID_STATUSES).count
    reservations_created = reservations_in_period.count

    {
      lead_to_paid_reservation: percent(reservations_paid, leads_total),
      lead_to_any_reservation: percent(reservations_created, leads_total),
      created_to_paid: percent(reservations_paid, reservations_created)
    }
  end

  def percent(numerator, denominator)
    return 0 if denominator.to_i.zero?

    (numerator.to_f / denominator * 100).round(1)
  end
end
