# Proxy interno que traduz OpenAI Chat Completions ↔ OpenAI Responses (Codex).
#
# Recebe requests no formato Chat Completions (o que RubyLLM, Agents gem e
# ruby-openai geram) e encaminha para a Responses API do ChatGPT Plus (Codex)
# usando OAuth interno via Captain::Codex::AuthService.
#
# Rota: POST /codex/v1/chat/completions
#
# Acesso: interno (não autenticado — localhost-only via Docker network).
# Em produção, o Nginx NÃO expõe /codex/* publicamente.
class Api::Internal::CodexProxyController < ApplicationController
  skip_before_action :verify_authenticity_token, raise: false

  def chat_completions
    chat_body = request.request_parameters.presence || parse_body
    return render_error('Empty request body', status: 400) if chat_body.blank?

    render json: proxy_call(chat_body)
  rescue Captain::Codex::AuthService::AuthError, Captain::Codex::Client::Error, StandardError => e
    handle_proxy_error(e)
  end

  private

  def handle_proxy_error(error)
    case error
    when Captain::Codex::AuthService::AuthError
      Rails.logger.error("[Codex Proxy] Auth error: #{error.message}")
      render_error("Codex auth error: #{error.message}", status: 401)
    when Captain::Codex::Client::Error
      Rails.logger.error("[Codex Proxy] Upstream error: #{error.message}")
      render_error("Upstream error: #{error.message}", status: error.http_status || 502)
    else
      Rails.logger.error("[Codex Proxy] Unexpected: #{error.class} #{error.message}\n#{error.backtrace.first(5).join("\n")}")
      render_error("Internal error: #{error.message}", status: 500)
    end
  end

  def proxy_call(chat_body)
    responses_body = Captain::Codex::Translator.chat_to_responses(chat_body)
    aggregated = Captain::Codex::Client.new.responses(responses_body)
    Captain::Codex::Translator.responses_to_chat(aggregated)
  end

  def parse_body
    raw = request.raw_post
    return {} if raw.blank?

    JSON.parse(raw)
  rescue JSON::ParserError
    {}
  end

  def render_error(message, status:)
    render json: { error: { message: message, type: 'codex_proxy_error' } }, status: status
  end
end
