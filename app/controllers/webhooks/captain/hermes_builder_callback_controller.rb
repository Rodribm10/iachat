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

  # Estratégia: usar o session_id do metadata (Hermes propaga o chat_id).
  # Fallback: account_id da query string + último user que mandou msg
  # (raro, mas evita perder resposta).
  def resolve_session_key
    chat_id = params[:metadata]&.[](:chat_id) || params.dig(:metadata, 'chat_id')
    if chat_id.is_a?(String) && chat_id.include?('builder-')
      # Formato: webhook:construtor-admin:session:builder-<account>-<user>
      session_id = chat_id.split(':').last
      return "hermes_builder:#{session_id}" if session_id.start_with?('builder-')
    end

    account_id = params[:account_id]
    return nil if account_id.blank?

    # Fallback: pega últimas 5 sessões do account, retorna a mais recente
    # com mensagens. Aceitável pra MVP com 1 admin testando por vez.
    recent_session_key_for(account_id)
  end

  def recent_session_key_for(account_id)
    return nil unless Rails.cache.respond_to?(:redis)

    pattern = "hermes_builder:builder-#{account_id}-*"
    keys = Rails.cache.redis.with { |c| c.keys(pattern) }
    return nil if keys.blank?

    keys.first.sub(/^.*?(hermes_builder:.*)$/, '\1')
  rescue StandardError => e
    Rails.logger.warn("[HermesBuilder::Callback] recent_session_key fallback failed: #{e.class} - #{e.message}")
    nil
  end
end
