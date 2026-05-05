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
class Api::V1::Accounts::Captain::HermesBuilderController < Api::V1::Accounts::BaseController
  before_action :authorize_admin

  def index
    msgs = HermesBuilder::Storage.messages_for(session_key)
    render json: { messages: msgs, session_id: session_id }
  end

  def create
    text = params[:text].to_s.strip
    return render json: { error: 'Texto vazio' }, status: :bad_request if text.blank?

    HermesBuilder::Storage.append(session_key, role: 'user', content: text)
    HermesBuilder::Storage.remember_last_session(Current.account.id, session_key)
    HermesBuilder::Dispatcher.send_to_construtor(session_id: session_id, message: text)

    render json: { ok: true, session_id: session_id }, status: :accepted
  rescue HermesBuilder::Dispatcher::DispatchError => e
    Rails.logger.error("[HermesBuilder#create] dispatch failed: #{e.message}")
    render json: { error: "Falha ao contatar Construtor: #{e.message}" }, status: :bad_gateway
  end

  # Inicia sessão limpa enviando comando-gatilho oculto pro Construtor pra
  # ele começar o fluxo socrático de criação. UI chama este endpoint
  # quando admin clica "Iniciar" — sem ter que digitar primeira msg.
  def start
    HermesBuilder::Storage.clear(session_key)
    HermesBuilder::Storage.remember_last_session(Current.account.id, session_key)
    HermesBuilder::Dispatcher.send_to_construtor(
      session_id: session_id,
      message: '__START__ Inicie o fluxo de criação de novo agente Hermes. Comece pela primeira pergunta do Bloco 1 (nome do agente).'
    )
    render json: { ok: true, session_id: session_id }, status: :accepted
  rescue HermesBuilder::Dispatcher::DispatchError => e
    Rails.logger.error("[HermesBuilder#start] dispatch failed: #{e.message}")
    render json: { error: "Falha ao contatar Construtor: #{e.message}" }, status: :bad_gateway
  end

  def reset
    HermesBuilder::Storage.clear(session_key)
    render json: { ok: true }
  end

  # Lista assistentes Hermes da conta atual pra dropdown da aba Verificação.
  def assistants
    rows = ::Captain::Assistant.where(account_id: Current.account.id, engine: 'hermes')
                               .order(:name)
                               .pluck(:id, :name, :hermes_profile_name)
                               .map { |id, name, slug| { id: id, name: name, slug: slug } }
    render json: { assistants: rows }
  end

  # Roda o validator (porta dos checks DB do CLI hermes-validate).
  def validate
    slug = params[:slug].to_s.strip
    return render json: { error: 'slug required' }, status: :bad_request if slug.blank?

    render json: HermesBuilder::Validator.run(slug)
  end

  # Aplica reparo automatizado pra um check FAIL/WARN específico.
  def repair
    slug = params[:slug].to_s.strip
    repair_id = params[:repair_id].to_s.strip
    return render json: { ok: false, error: 'slug e repair_id required' }, status: :bad_request if slug.blank? || repair_id.blank?

    result = HermesBuilder::Repairer.repair(slug: slug, repair_id: repair_id)
    render json: result, status: result[:ok] ? :ok : :unprocessable_entity
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
