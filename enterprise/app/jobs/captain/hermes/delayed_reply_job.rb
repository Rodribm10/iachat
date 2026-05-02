# Posta a resposta do Hermes na conversa simulando comportamento humano:
# 1. Liga indicador de "digitando..." (composing) via wuzapi
# 2. Aguarda delay configurado pelo assistant (typing_simulation, fixed ou none)
# 3. Posta a mensagem outgoing
#
# Config vive em `Captain::Assistant.config['response_delay']`:
#   {
#     "mode": "typing_simulation" | "fixed" | "none",
#     "chars_per_second": 25,        # apenas typing_simulation
#     "seconds": 3,                  # apenas fixed
#     "min_seconds": 1.5,            # cap inferior pra typing_simulation
#     "max_seconds": 8.0             # cap superior pra typing_simulation
#   }
#
# Default: none (zero delay, igual antes — defensivo).
class Captain::Hermes::DelayedReplyJob < ApplicationJob
  queue_as :default

  DEFAULT_CONFIG = {
    'mode' => 'none',
    'chars_per_second' => 25,
    'min_seconds' => 1.5,
    'max_seconds' => 8.0
  }.freeze

  def perform(conversation_id, content)
    conversation = Conversation.find_by(id: conversation_id)
    if conversation.blank?
      Rails.logger.warn("[Captain::Hermes::DelayedReplyJob] conv #{conversation_id} not found")
      return
    end

    delay = compute_delay(conversation, content)

    if delay.positive?
      send_typing(conversation, 'typing_on')
      sleep(delay)
    end

    create_outgoing_message(conversation, content)

    # NÃO mandamos typing_off explícito — WhatsApp cancela o indicador
    # automaticamente quando a msg chega no celular. Mandar paused agora
    # quebraria visualmente: typing some -> gap de 2-5s ate msg ser
    # entregue via SendReplyJob -> msg chega. Deixa o WhatsApp gerenciar.
  end

  private

  def compute_delay(conversation, content)
    cfg = DEFAULT_CONFIG.merge(conversation.inbox.captain_assistant&.config.to_h.fetch('response_delay', {}))
    case cfg['mode']
    when 'fixed' then cfg['seconds'].to_f
    when 'typing_simulation'
      cps = cfg['chars_per_second'].to_f
      cps = 25 if cps <= 0
      raw = content.to_s.length / cps
      raw.clamp(cfg['min_seconds'].to_f, cfg['max_seconds'].to_f)
    else 0.0
    end
  end

  def send_typing(conversation, status)
    return unless conversation.inbox.respond_to?(:channel)
    return unless conversation.inbox.channel.respond_to?(:toggle_typing_status)

    conversation.inbox.channel.toggle_typing_status(status, conversation: conversation)
  rescue StandardError => e
    Rails.logger.warn("[Captain::Hermes::DelayedReplyJob] toggle_typing_status #{status} failed: #{e.class} - #{e.message}")
  end

  def create_outgoing_message(conversation, content)
    assistant = conversation.inbox.captain_assistant
    sender = assistant.presence || User.find_by(id: conversation.assignee_id)

    conversation.messages.create!(
      message_type: :outgoing,
      account_id: conversation.account_id,
      inbox_id: conversation.inbox_id,
      sender: sender,
      content: content,
      content_attributes: { external_source: 'hermes_callback' }
    )
  end
end
