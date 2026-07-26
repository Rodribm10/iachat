# Expõe a saúde das conexões do Captain para a sonda do OS Foco.
#
# Por que HTTP e não SSH: o servidor do OS Foco (servidorhouse) não tem acesso
# SSH à VPS do Chatwoot, e criar essa chave só para ler saúde ampliaria a
# superfície bem mais do que uma rota autenticada somente-leitura.
#
# Autenticação: `Authorization: Bearer <CAPTAIN_HEALTH_SECRET>`, mesmo padrão
# do webhook MCP. Sem o segredo configurado a rota responde 404 — nunca fica
# aberta por esquecimento, que é o modo de falha real desse tipo de endpoint.
#
# Não expõe conteúdo de conversa nem dado de cliente: só nome da conexão,
# estado e uma frase de diagnóstico.
class Webhooks::Captain::HealthController < ApplicationController
  skip_before_action :verify_authenticity_token, raise: false
  before_action :verify_secret

  def show
    render json: Captain::Health::ConexoesService.new.call
  rescue StandardError => e
    Rails.logger.error("[Captain::Health] falha ao apurar: #{e.class}: #{e.message}")
    render json: { erro: "#{e.class}: #{e.message}" }, status: :internal_server_error
  end

  private

  def verify_secret
    secret = ENV.fetch('CAPTAIN_HEALTH_SECRET', nil).presence ||
             InstallationConfig.find_by(name: 'CAPTAIN_HEALTH_SECRET')&.value.presence

    # Sem segredo a rota não existe: 404 em vez de 401 não confirma para um
    # curioso que há algo aqui.
    return head :not_found if secret.blank?

    head :unauthorized unless bearer_matches?(secret)
  end

  def bearer_matches?(secret)
    header = request.headers['Authorization'].to_s
    return false unless header.start_with?('Bearer ')

    ActiveSupport::SecurityUtils.secure_compare(header.delete_prefix('Bearer ').strip, secret)
  end
end
