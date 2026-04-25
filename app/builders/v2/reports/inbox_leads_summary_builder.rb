class V2::Reports::InboxLeadsSummaryBuilder
  include DateRangeHelper

  ALLOWED_GROUP_BY = %w[day week month].freeze
  RETURN_THRESHOLD = '24 hours'.freeze

  attr_reader :account, :params

  def initialize(account, params)
    @account = account
    @params = params
  end

  def build
    return [] if range.blank? || inbox.blank?

    rows = ActiveRecord::Base.connection.exec_query(
      ActiveRecord::Base.sanitize_sql_array([sql, sql_bindings])
    )

    rows.map do |row|
      {
        period: row['period'].iso8601,
        new_leads: row['new_leads'].to_i,
        returning: row['returning'].to_i,
        others: row['others'].to_i
      }
    end
  end

  private

  def inbox
    @inbox ||= account.inboxes.find_by(id: params[:inbox_id])
  end

  def group_by
    value = params[:group_by].to_s
    ALLOWED_GROUP_BY.include?(value) ? value : 'day'
  end

  def sql_bindings
    {
      account_id: account.id,
      inbox_id: inbox.id,
      since: range.begin,
      until_t: range.end,
      group_by: group_by,
      return_threshold: RETURN_THRESHOLD
    }
  end

  # Single CTE to classify each conversation in the period as:
  #   * new_leads:  contact has no prior conversation in any inbox of the account
  #   * returning:  contact had a prior conversation whose latest 'conversation_resolved'
  #                 event occurred more than 24h before the new conversation
  #   * others:     prior conversation existed but was not resolved or was resolved <24h ago
  # rubocop:disable Metrics/MethodLength
  def sql
    <<~SQL.squish
      WITH period_conversations AS (
        SELECT id, contact_id, created_at
        FROM conversations
        WHERE account_id = :account_id
          AND inbox_id = :inbox_id
          AND created_at >= :since
          AND created_at < :until_t
      ),
      classified AS (
        SELECT
          c.id,
          c.created_at,
          EXISTS (
            SELECT 1 FROM conversations prev
            WHERE prev.contact_id = c.contact_id
              AND prev.account_id = :account_id
              AND prev.id < c.id
          ) AS has_prior,
          (
            SELECT MAX(re.created_at)
            FROM reporting_events re
            INNER JOIN conversations prev ON prev.id = re.conversation_id
            WHERE re.name = 'conversation_resolved'
              AND prev.contact_id = c.contact_id
              AND prev.account_id = :account_id
              AND prev.id < c.id
          ) AS latest_prior_resolution_at
        FROM period_conversations c
      )
      SELECT
        date_trunc(:group_by, created_at) AS period,
        COUNT(*) FILTER (WHERE NOT has_prior) AS new_leads,
        COUNT(*) FILTER (
          WHERE has_prior
            AND latest_prior_resolution_at IS NOT NULL
            AND latest_prior_resolution_at < created_at - (:return_threshold)::interval
        ) AS returning,
        COUNT(*) FILTER (
          WHERE has_prior
            AND (
              latest_prior_resolution_at IS NULL
              OR latest_prior_resolution_at >= created_at - (:return_threshold)::interval
            )
        ) AS others
      FROM classified
      GROUP BY period
      ORDER BY period
    SQL
  end
  # rubocop:enable Metrics/MethodLength
end
