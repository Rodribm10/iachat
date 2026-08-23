# Liga e desliga o "digitando…" do canal enquanto o agente do Hermes pensa.
#
# O Chatwoot só dispara typing quando um agente humano digita no dashboard —
# não existe nada que faça isso pelo bot. O gateway do Hermes chama esta rota
# ao começar a processar a mensagem do cliente e de novo ao devolver a resposta:
#
#   POST /webhooks/captain/typing?inbox_id=<id>&conversation_internal_id=<id>
#   Body: { "typing_status": "on" | "off" }
#
# Mesma assinatura HMAC do hermes_callback (X-Hermes-Callback-Signature).
class Webhooks::Captain::TypingController < ApplicationController
  skip_before_action :verify_authenticity_token, raise: false
  before_action :verify_signature
  before_action :fetch_conversation

  def toggle
    channel = @conversation.inbox.channel
    return head :ok unless channel.respond_to?(:toggle_typing_status)

    channel.toggle_typing_status(typing_event, conversation: @conversation)
    head :ok
  rescue StandardError => e
    # Indicador de presença é enfeite: nunca pode derrubar o turno do agente.
    Rails.logger.warn("[Hermes::Typing] #{e.class}: #{e.message}")
    head :ok
  end

  private

  def typing_event
    return Events::Types::CONVERSATION_TYPING_OFF if params[:typing_status].to_s == 'off'

    Events::Types::CONVERSATION_TYPING_ON
  end

  def verify_signature
    secret = Captain::Hermes.callback_signing_secret
    return true if secret.blank?

    signature = request.headers['X-Hermes-Callback-Signature'].to_s
    return head :unauthorized if signature.blank?

    expected = "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', secret, request.raw_post)}"
    return head :unauthorized unless ActiveSupport::SecurityUtils.secure_compare(signature, expected)

    true
  end

  def fetch_conversation
    inbox = Inbox.find_by(id: params[:inbox_id])
    return head :not_found if inbox.blank?

    internal_id = params[:conversation_internal_id].presence
    display_id = params[:conversation_id].presence
    @conversation = inbox.conversations.find_by(id: internal_id) if internal_id.present?
    @conversation ||= inbox.conversations.find_by(display_id: display_id) if display_id.present?

    head :not_found if @conversation.blank?
  end
end
