# Configuração compartilhada da integração Captain ↔ Hermes Agent.
#
# A integração usa o Hermes como cérebro do atendimento (Nível 2):
#   - Captain recebe msg WhatsApp
#   - Dispara webhook do Hermes (POST /webhooks/captain-inbox-<id>)
#   - Hermes processa via subscription Codex/etc dele
#   - Hermes invoca plugin captain-http-callback que POSTa de volta no Captain
#   - Captain cria mensagem outgoing e envia pro WhatsApp
#
# A ativação é por inbox via env var. As 9 outras inboxes do Captain seguem
# usando o orquestrador interno (Daniela_Reservas, etc) sem mudança.
#
# Env vars:
#   CAPTAIN_HERMES_INBOX_IDS              CSV de inbox.id (ex: "1,5"). Se vazio,
#                                          desativa em todas. Inboxes não listadas
#                                          continuam no fluxo Captain interno.
#   CAPTAIN_HERMES_WEBHOOK_BASE_URL       Base URL do gateway Hermes
#                                          (default http://172.17.0.1:8644).
#   CAPTAIN_HERMES_CALLBACK_SECRET        HMAC-SHA256 secret pra validar callback
#                                          do Hermes (X-Hermes-Callback-Signature).
#                                          Se vazio, validação é desabilitada (NÃO
#                                          recomendado em prod).
#   CAPTAIN_HERMES_SUBSCRIPTION_SECRET_INBOX_<id>
#                                          Per-inbox secret retornado pelo
#                                          `hermes webhook subscribe`. Usado pra
#                                          assinar o POST OUTGOING. Sem ele, o
#                                          Hermes vai rejeitar o webhook.
module Captain::Hermes
  DEFAULT_BASE_URL = 'http://172.17.0.1:8644'.freeze

  module_function

  def enabled_for?(inbox)
    return false if inbox.blank?
    return false unless inbox.respond_to?(:id)

    inbox_ids.include?(inbox.id)
  end

  def inbox_ids
    @inbox_ids ||= ENV.fetch('CAPTAIN_HERMES_INBOX_IDS', '')
                      .split(',')
                      .map { |s| s.strip.to_i }
                      .reject(&:zero?)
                      .freeze
  end

  def webhook_base_url
    @webhook_base_url ||= (ENV['CAPTAIN_HERMES_WEBHOOK_BASE_URL'].presence || DEFAULT_BASE_URL).chomp('/')
  end

  def webhook_url_for(inbox)
    "#{webhook_base_url}/webhooks/#{subscription_name_for(inbox)}"
  end

  # Convenção de nome de subscription no Hermes: precisa bater com o que o
  # admin criou via `hermes webhook subscribe captain-inbox-<id> ...`.
  def subscription_name_for(inbox)
    "captain-inbox-#{inbox.id}"
  end

  def subscription_signing_secret(inbox)
    ENV.fetch("CAPTAIN_HERMES_SUBSCRIPTION_SECRET_INBOX_#{inbox.id}", nil)
  end

  def callback_signing_secret
    ENV.fetch('CAPTAIN_HERMES_CALLBACK_SECRET', nil)
  end

  # Reseta caches. Útil em specs ou após reload de config.
  def reset_cache!
    @inbox_ids = nil
    @webhook_base_url = nil
  end
end
