# Operação por operador (réplica do bloco "Operação por Operador" do Sinal).
# "Minutos logados" não tem fonte no Chatwoot (presença é Redis efêmero) —
# no lugar entra o status online ao vivo + última resposta.
class V2::Reports::Sinal::OperationsBuilder < V2::Reports::Sinal::BaseBuilder
  def build
    { agents: agents }
  end

  private

  def human_messages
    messages_scope.where(created_at: range, message_type: :outgoing, sender_type: 'User')
                  .where.not(sender_id: nil)
  end

  # rubocop:disable Metrics/AbcSize
  def agents
    sent = human_messages.group(:sender_id).count
    handled_by_agent = human_messages.group(:sender_id).distinct.count(:conversation_id)
    last_message = human_messages.group(:sender_id).maximum(:created_at)
    reply_avg = reporting_events_scope(:reply_time).group(:user_id).average(:value)
    online_ids = OnlineStatusTracker.get_available_users(account.id) || {}

    rows = account.users.filter_map do |user|
      next unless sent.key?(user.id) || reply_avg.key?(user.id)

      {
        agent_id: user.id,
        agent_name: user.name,
        messages_sent: sent[user.id] || 0,
        conversations_handled: handled_by_agent[user.id] || 0,
        avg_response_minutes: reply_avg[user.id] ? (reply_avg[user.id] / 60.0).round : nil,
        last_message_at: last_message[user.id],
        online: online_ids[user.id.to_s] == 'online'
      }
    end
    rows.sort_by { |row| -row[:messages_sent] }
  end
  # rubocop:enable Metrics/AbcSize
end
