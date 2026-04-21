# Fornece o CEO Digest (via Captain::Reports::CeoDigestService) para a UI
# + endpoint de drill-down (busca conversas que contêm um texto) + disparo on-demand
# do envio ao Mattermost.
class Api::V1::Accounts::Captain::Reports::ExecutiveController < Api::V1::Accounts::BaseController
  # GET /api/v1/accounts/:account_id/captain/reports/executive
  # Params: period_start, period_end
  def show
    period_end = parse_date(params[:period_end], Time.zone.today - 1)
    period_start = parse_date(params[:period_start], period_end - 6.days)

    digest = Captain::Reports::CeoDigestService.new(
      account: Current.account,
      period_start: period_start,
      period_end: period_end
    ).call

    render json: digest
  end

  # GET /api/v1/accounts/:account_id/captain/reports/executive/drilldown
  # Params: query (texto a procurar), period_start, period_end, inbox_id (opcional)
  # Retorna: conversas que contêm o texto, com link para abrir no Chatwoot.
  def drilldown
    query = params[:query].to_s.strip
    return render json: { conversations: [] } if query.blank?

    period_end = parse_date(params[:period_end], Time.zone.today - 1)
    period_start = parse_date(params[:period_start], period_end - 6.days)
    inbox_id = params[:inbox_id].presence&.to_i

    conversations = search_conversations(query, period_start, period_end, inbox_id)
    tokens = extract_tokens(query)
    render json: { query: query, conversations: conversations, tokens: tokens }
  end

  # POST /api/v1/accounts/:account_id/captain/reports/executive/deliver
  # Dispara entrega do digest ao Mattermost agora (usa config da conta).
  def deliver
    period_end = parse_date(params[:period_end], Time.zone.today - 1)
    period_start = parse_date(params[:period_start], period_end - 6.days)

    Captain::Reports::CeoDigestJob.perform_later(Current.account.id, period_start, period_end)
    render json: { status: 'queued', period_start: period_start, period_end: period_end }, status: :accepted
  end

  private

  def search_conversations(query, period_start, period_end, inbox_id)
    tokens = extract_tokens(query)
    return [] if tokens.empty?

    scope = Current.account.conversations
                   .where(created_at: period_start.beginning_of_day..period_end.end_of_day)
                   .joins(:messages)
    scope = scope.where(inbox_id: inbox_id) if inbox_id
    scope = apply_token_filter(scope, tokens)
    scope.distinct.includes(:contact, :inbox).limit(10).map { |c| format_conversation(c) }
  end

  # Quebra a descrição do insight em palavras relevantes (4+ chars, sem stopwords)
  # e retorna só os tokens mais distintivos. Assim "Facilidade no acesso ao link
  # de pagamento" vira ["facilidade", "acesso", "link", "pagamento"].
  STOPWORDS = %w[
    para com que uma esse essa esta isso aqui ali mais menos sobre entre
    sem nao sim the and for that this with from into have need want
    sobre quando onde como porque qual quais nesse nessa dessa desse dele
    dela dos das pelo pela pelos pelas deste desta disto isto foi ser
  ].freeze

  def extract_tokens(query)
    query.to_s.downcase
         .scan(/[[:alnum:]áéíóúâêôãõçàü]+/)
         .reject { |w| w.length < 4 || STOPWORDS.include?(w) }
         .uniq
         .first(8)
  end

  def apply_token_filter(scope, tokens)
    conditions = Array.new(tokens.size, 'messages.content ILIKE ?').join(' OR ')
    values = tokens.map { |t| "%#{sanitize_like(t)}%" }
    scope.where(conditions, *values)
  end

  def sanitize_like(str)
    str.gsub('\\', '\\\\').gsub('%', '\\%').gsub('_', '\\_')
  end

  def format_conversation(conv)
    {
      id: conv.display_id,
      internal_id: conv.id,
      status: conv.status,
      inbox_id: conv.inbox_id,
      inbox_name: conv.inbox&.name,
      contact_name: conv.contact&.name,
      created_at: conv.created_at,
      updated_at: conv.updated_at,
      url: conversation_url(conv)
    }
  end

  def conversation_url(conv)
    "/app/accounts/#{Current.account.id}/conversations/#{conv.display_id}"
  end

  def parse_date(param, default)
    return default if param.blank?

    Date.parse(param.to_s)
  rescue ArgumentError, TypeError
    default
  end
end
