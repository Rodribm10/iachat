# Calcula estatísticas de interação e recorrência de um contato.
#
# Regras (negociadas com Rodrigo em 2026-04-22):
# - Gap de 30h entre a última msg de uma interação e a próxima msg do contato
#   define o limite entre interações distintas. Abaixo de 30h é a mesma "sessão".
# - Interação QUALIFICADA: ≥ MIN_CUSTOMER_MSGS mensagens do contato E
#   ≥ MIN_BOT_MSGS mensagens de atendimento (bot ou humano), cada uma com
#   conteúdo textual (>= 2 letras, não só emoji/sticker/anexo).
# - Interação ONE-SHOT: teve troca (≥1 de cada lado) mas não atingiu o
#   limiar de qualificada. É registrada como métrica secundária.
# - Conversas silenciosas (sem resposta) não viram interação de nenhum tipo.
# - Contatos com label 'equipe_interna' são excluídos de todas as métricas
#   (marca manual pra filtrar gerentes, testes, etc).
#
# O service é puro — não persiste. RecalculateJob cuida da persistência.
class Captain::ContactStats::InteractionCalculatorService
  INTERACTION_GAP = 30.hours
  INTERNAL_LABEL = 'equipe_interna'.freeze
  MIN_CUSTOMER_MSGS = 2
  MIN_BOT_MSGS = 2

  EMPTY_STATS = {
    interactions_count: 0,
    one_shot_consultations_count: 0,
    first_interaction_at: nil,
    last_interaction_at: nil,
    is_recurring: false
  }.freeze

  def initialize(contact:)
    @contact = contact
  end

  def call
    return EMPTY_STATS.dup if internal?

    messages = load_relevant_messages
    return EMPTY_STATS.dup if messages.empty?

    groups = group_into_interactions(messages)
    qualified_count, one_shot_count = classify_groups(groups)

    {
      interactions_count: qualified_count,
      one_shot_consultations_count: one_shot_count,
      first_interaction_at: groups.first[:first_at],
      last_interaction_at: groups.last[:last_at],
      is_recurring: qualified_count >= 2
    }
  end

  private

  def internal?
    @contact.label_list.include?(INTERNAL_LABEL)
  rescue StandardError
    false
  end

  # Puxa toda msg pública não-falha de conversas do contato.
  # Inclui msgs de Contact (cliente) e outgoing (bot ou agente humano).
  # Ordem cronológica global pra reconstruir linhas do tempo.
  def load_relevant_messages
    Message
      .joins(:conversation)
      .where(conversations: { contact_id: @contact.id })
      .where(private: false)
      .where.not(status: :failed)
      .where(message_type: %i[incoming outgoing])
      .order(:created_at)
  end

  # Varre mensagens na ordem cronológica e abre uma nova interação sempre
  # que o intervalo entre a mensagem atual e a última da interação corrente
  # for maior que INTERACTION_GAP.
  def group_into_interactions(messages)
    groups = []
    current = nil

    messages.each do |msg|
      if current.nil? || (msg.created_at - current[:last_at]) > INTERACTION_GAP
        current = { first_at: msg.created_at, last_at: msg.created_at, messages: [msg] }
        groups << current
      else
        current[:messages] << msg
        current[:last_at] = msg.created_at
      end
    end

    groups
  end

  def classify_groups(groups)
    qualified = 0
    one_shot = 0

    groups.each do |group|
      customer = group[:messages].count { |m| qualified_customer_message?(m) }
      bot = group[:messages].count { |m| qualified_bot_message?(m) }

      next if customer.zero? || bot.zero?

      if customer >= MIN_CUSTOMER_MSGS && bot >= MIN_BOT_MSGS
        qualified += 1
      else
        one_shot += 1
      end
    end

    [qualified, one_shot]
  end

  def qualified_customer_message?(msg)
    msg.message_type == 'incoming' &&
      msg.sender_type == 'Contact' &&
      text_content?(msg)
  end

  # Resposta de atendimento conta se é outgoing da Jasmine (Captain::Assistant)
  # ou de um agente humano (User). Mensagens de sistema (sender_type nil ou
  # AgentBot) ficam de fora — são transferências/automações, não engajamento.
  def qualified_bot_message?(msg)
    return false unless msg.message_type == 'outgoing'

    %w[Captain::Assistant User].include?(msg.sender_type) && text_content?(msg)
  end

  # Conteúdo textual válido: pelo menos 2 letras. Exclui emoji-só, sticker,
  # anexo sem legenda, placeholder "Message without content".
  def text_content?(msg)
    content = msg.content.to_s.strip
    return false if content.blank?
    return false if content == 'Message without content'

    content.scan(/\p{L}/).length >= 2
  end
end
