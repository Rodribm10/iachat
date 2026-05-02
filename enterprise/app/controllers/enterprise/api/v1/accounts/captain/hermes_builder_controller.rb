# Endpoints da UI Hermes Builder no painel Captain.
#
# Fluxo:
#   1. UI faz POST /messages com texto do admin
#   2. Backend encaminha pro gateway Hermes Construtor (porta 8646 na VPS)
#   3. Construtor processa async e dispara http_callback (HermesBuilderCallbackController)
#   4. Callback armazena resposta no Rails.cache
#   5. UI faz GET /messages a cada 2s (polling) e renderiza
#
# Sessão é por account+user (1 admin → 1 sessão de builder por vez).
class Enterprise::Api::V1::Accounts::Captain::HermesBuilderController < Api::V1::Accounts::BaseController
  before_action :authorize_admin

  def index
    msgs = HermesBuilder::Storage.messages_for(session_key)
    render json: { messages: msgs, session_id: session_id }
  end

  def create
    text = params[:text].to_s.strip
    return render json: { error: 'Texto vazio' }, status: :bad_request if text.blank?

    HermesBuilder::Storage.append(session_key, role: 'user', content: text)
    HermesBuilder::Dispatcher.send_to_construtor(session_id: session_id, message: text)

    render json: { ok: true, session_id: session_id }, status: :accepted
  rescue HermesBuilder::Dispatcher::DispatchError => e
    Rails.logger.error("[HermesBuilder#create] dispatch failed: #{e.message}")
    render json: { error: "Falha ao contatar Construtor: #{e.message}" }, status: :bad_gateway
  end

  def reset
    HermesBuilder::Storage.clear(session_key)
    render json: { ok: true }
  end

  private

  def authorize_admin
    return if current_user&.administrator?

    render json: { error: 'Apenas administradores podem usar o Builder' }, status: :forbidden
  end

  # Sessão é por (account, user). Hermes Construtor mantém memória estável
  # graças ao plugin captain-webhook que rewrita chat_id usando hermes_session_id.
  def session_id
    "builder-#{Current.account.id}-#{current_user.id}"
  end

  def session_key
    "hermes_builder:#{session_id}"
  end
end
