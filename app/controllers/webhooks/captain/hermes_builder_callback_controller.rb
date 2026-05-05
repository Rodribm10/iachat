# Recebe callback do Hermes Construtor (plugin captain-http-callback).
#
# Construtor responde async via POST pra esta URL com:
#   { content: "<resposta>", reply_to: ..., metadata: {...}, timestamp: ... }
#
# Este controller identifica a sessão do admin (por session_id no metadata
# OU pelo cache key derivado de account_id que veio na query string) e
# armazena a resposta no Rails.cache pra UI poder ler via polling.
class Webhooks::Captain::HermesBuilderCallbackController < ApplicationController
  skip_before_action :verify_authenticity_token, raise: false

  def process_payload
    content = params[:content].to_s.strip
    return head :bad_request if content.blank?

    session_key = resolve_session_key
    if session_key.blank?
      Rails.logger.warn('[HermesBuilder::Callback] no session_key resolvable — ignorando')
      return head :ok
    end

    HermesBuilder::Storage.append(session_key, role: 'construtor', content: content)
    Rails.logger.info("[HermesBuilder::Callback] reply received for #{session_key} (#{content.length} chars)")

    head :ok
  rescue StandardError => e
    Rails.logger.error("[HermesBuilder::Callback] error: #{e.class}: #{e.message}")
    head :internal_server_error
  end

  private

  # Hermes nao propaga chat_id no metadata da resposta de callback, entao
  # usamos a ultima sessao ativa do account (gravada por
  # HermesBuilder::Storage.remember_last_session no /start e /create).
  # MVP-safe pra 1 admin por vez por conta.
  def resolve_session_key
    account_id = params[:account_id]
    return nil if account_id.blank?

    HermesBuilder::Storage.last_session_for(account_id)
  end
end
