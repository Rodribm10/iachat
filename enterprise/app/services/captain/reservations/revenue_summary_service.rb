class Captain::Reservations::RevenueSummaryService
  def initialize(scope:)
    @scope = scope
  end

  def perform
    {
      summary: {
        total_revenue: total_revenue,
        confirmed_count: confirmed_count,
        average_ticket: average_ticket
      },
      by_unit: grouped_revenue_by_unit,
      by_suite: grouped_revenue_by_suite
    }
  end

  private

  attr_reader :scope

  def total_revenue
    scope.sum(:total_amount).to_f
  end

  def confirmed_count
    scope.count
  end

  def average_ticket
    return 0.0 unless confirmed_count.positive?

    total_revenue / confirmed_count
  end

  def grouped_revenue_by_unit
    scope.left_joins(:unit)
         .group('captain_units.id', 'captain_units.name')
         .order(Arel.sql('COALESCE(SUM(captain_reservations.total_amount), 0) DESC'))
         .pluck(
           'captain_units.id',
           'captain_units.name',
           Arel.sql('COUNT(captain_reservations.id)'),
           Arel.sql('COALESCE(SUM(captain_reservations.total_amount), 0)')
         )
         .map do |unit_id, unit_name, count, amount|
      {
        unit_id: unit_id,
        unit_name: unit_name,
        reservations_count: count.to_i,
        total_revenue: amount.to_f
      }
    end
  end

  def grouped_revenue_by_suite
    scope.group(:suite_identifier)
         .order(Arel.sql('COALESCE(SUM(captain_reservations.total_amount), 0) DESC'))
         .pluck(
           :suite_identifier,
           Arel.sql('COUNT(captain_reservations.id)'),
           Arel.sql('COALESCE(SUM(captain_reservations.total_amount), 0)')
         )
         .map do |suite_identifier, count, amount|
      {
        suite_identifier: suite_identifier,
        reservations_count: count.to_i,
        total_revenue: amount.to_f
      }
    end
  end
end
