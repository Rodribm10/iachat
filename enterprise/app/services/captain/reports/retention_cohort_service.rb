# Gera a matriz de cohort mensal de retenção por interação.
#
# Linha = cohort (mês em que o contato teve a primeira interação).
# Coluna = offset em meses (M+0, M+1, M+2, ..., M+12).
# Célula = % de contatos daquela cohort que tiveram QUALQUER mensagem
#          no mês M+N.
#
# Granularidade mensal dispensa o gap de 30h do InteractionCalculator:
# se o contato teve qualquer msg em um mês, conta como retido naquele mês.
# A imprecisão de dedup por hora fica embutida dentro do bucket mensal.
#
# O cálculo é uma agregação SQL só, sem varrer contato a contato.
class Captain::Reports::RetentionCohortService
  DEFAULT_HISTORY_MONTHS = 12
  MAX_OFFSET_MONTHS = 12

  def initialize(account:, history_months: DEFAULT_HISTORY_MONTHS)
    @account = account
    @history_months = history_months.to_i.clamp(1, 24)
  end

  def call
    sizes = cohort_sizes
    activity = cohort_activity(sizes.keys)

    {
      generated_at: Time.current.iso8601,
      history_months: @history_months,
      max_offset_months: MAX_OFFSET_MONTHS,
      cohorts: build_cohort_rows(sizes, activity)
    }
  end

  private

  def build_cohort_rows(sizes, activity)
    sizes.sort.reverse.map do |cohort_month, size|
      {
        cohort: cohort_month.iso8601,
        size: size,
        retention: build_retention_row(cohort_month, size, activity)
      }
    end
  end

  def build_retention_row(cohort_month, size, activity)
    (0..MAX_OFFSET_MONTHS).map do |offset|
      active = activity.dig(cohort_month, cohort_month >> offset) || 0
      rate = size.zero? ? 0.0 : (active.to_f / size).round(4)
      { month_offset: offset, count: active, rate: rate }
    end
  end

  # Retorna { Date => Integer }: chave é o 1º dia do mês da cohort, valor é
  # a quantidade de contatos na cohort.
  def cohort_sizes
    start_month = (Time.current - @history_months.months).beginning_of_month

    rows = @account.contacts
                   .where.not(first_interaction_at: nil)
                   .where('first_interaction_at >= ?', start_month)
                   .group(Arel.sql("DATE_TRUNC('month', first_interaction_at)"))
                   .count

    rows.transform_keys { |ts| ts.to_date.beginning_of_month }
  end

  # Retorna { cohort_month => { activity_month => count } }
  # Monta só os cohorts passados e considera atividade até hoje.
  def cohort_activity(cohort_months)
    return {} if cohort_months.empty?

    start_month = cohort_months.min
    end_month = Time.current.beginning_of_month

    sql = activity_sql(start_month, end_month)
    rows = ActiveRecord::Base.connection.exec_query(sql, 'RetentionCohort')

    hash = Hash.new { |h, k| h[k] = {} }

    rows.each do |row|
      cohort_month = row['cohort_month'].to_date.beginning_of_month
      activity_month = row['activity_month'].to_date.beginning_of_month
      hash[cohort_month][activity_month] = row['active_contacts'].to_i
    end

    hash
  end

  # rubocop:disable Metrics/MethodLength
  def activity_sql(start_month, end_month)
    ActiveRecord::Base.sanitize_sql_array([
                                            <<~SQL.squish,
                                              WITH contact_cohorts AS (
                                                SELECT id AS contact_id,
                                                       DATE_TRUNC('month', first_interaction_at) AS cohort_month
                                                FROM contacts
                                                WHERE first_interaction_at IS NOT NULL
                                                  AND first_interaction_at >= ?
                                                  AND account_id = ?
                                              ),
                                              contact_activity AS (
                                                SELECT DISTINCT
                                                       conversations.contact_id,
                                                       DATE_TRUNC('month', messages.created_at) AS activity_month
                                                FROM messages
                                                INNER JOIN conversations ON conversations.id = messages.conversation_id
                                                WHERE messages.sender_type = 'Contact'
                                                  AND messages.private = false
                                                  AND (messages.status IS NULL OR messages.status <> ?)
                                                  AND conversations.account_id = ?
                                                  AND messages.created_at >= ?
                                                  AND messages.created_at < ?
                                              )
                                              SELECT c.cohort_month,
                                                     a.activity_month,
                                                     COUNT(DISTINCT c.contact_id) AS active_contacts
                                              FROM contact_cohorts c
                                              INNER JOIN contact_activity a ON a.contact_id = c.contact_id
                                              WHERE a.activity_month >= c.cohort_month
                                              GROUP BY c.cohort_month, a.activity_month
                                              ORDER BY c.cohort_month, a.activity_month
                                            SQL
                                            start_month,
                                            @account.id,
                                            failed_status_value,
                                            @account.id,
                                            start_month,
                                            end_month + 1.month
                                          ])
  end
  # rubocop:enable Metrics/MethodLength

  # Message.statuses['failed'] retorna o integer do enum.
  def failed_status_value
    Message.statuses['failed']
  end
end
