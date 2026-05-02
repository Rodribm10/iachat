# Configuração compartilhada da integração Captain ↔ Hermes Agent.
#
# A integração usa o Hermes como cérebro do atendimento (Nível 2):
#   - Captain recebe msg WhatsApp
#   - Dispara webhook do Hermes (POST /webhooks/captain-inbox-<id>)
#   - Hermes processa via subscription Codex/etc dele
#   - Hermes invoca plugin captain-http-callback que POSTa de volta no Captain
#   - Captain cria mensagem outgoing e envia pro WhatsApp
#
# A ativação preferencial é DATA-DRIVEN: cada Captain::Assistant tem coluna
# `engine` ('captain_interno' | 'hermes'). Inboxes apontam pra um assistant
# via CaptainInbox; o engine do assistant determina o roteamento. Trocar de
# engine = trocar a association no painel, sem deploy.
#
# Por compatibilidade durante a migração (gradual), também respeitamos as
# env vars antigas: se uma inbox está em CAPTAIN_HERMES_INBOX_IDS mas o
# assistant ainda é 'captain_interno', tratamos como Hermes — assim Valentina
# continua funcionando antes do admin re-apontar a inbox no painel.
# Esse fallback deve ser removido depois que todos as inboxes migrarem.
#
# Env vars (apenas credenciais — config funcional vive no DB):
#   CAPTAIN_HERMES_CALLBACK_SECRET        HMAC-SHA256 secret pra validar
#                                          callback do Hermes
#                                          (X-Hermes-Callback-Signature).
#   CAPTAIN_HERMES_SUBSCRIPTION_SECRET_INBOX_<id>
#                                          Per-inbox secret retornado pelo
#                                          `hermes webhook subscribe`. Usado
#                                          pra assinar o POST OUTGOING.
#
# Env vars LEGACY (em descontinuação — preferir DB):
#   CAPTAIN_HERMES_INBOX_IDS              CSV de inbox.id. Usado só como
#                                          fallback até as inboxes terem
#                                          assistant com engine='hermes'.
#   CAPTAIN_HERMES_WEBHOOK_BASE_URL       Base URL default. Idem.
#   CAPTAIN_HERMES_BASE_URL_INBOX_<id>    Per-inbox base URL. Idem.
module Captain::Hermes
  DEFAULT_BASE_URL = 'http://172.17.0.1:8644'.freeze

  module_function

  def enabled_for?(inbox)
    return false if inbox.blank?
    return false unless inbox.respond_to?(:id)

    return true if assistant_for(inbox)&.hermes?

    legacy_inbox_ids.include?(inbox.id)
  end

  def assistant_for(inbox)
    return nil if inbox.blank?
    return nil unless inbox.respond_to?(:captain_inbox)

    inbox.captain_inbox&.captain_assistant
  end

  def webhook_base_url(inbox = nil)
    assistant = assistant_for(inbox)
    return assistant.hermes_webhook_base_url.chomp('/') if assistant&.hermes? && assistant.hermes_webhook_base_url.present?

    legacy_webhook_base_url(inbox)
  end

  def webhook_url_for(inbox)
    "#{webhook_base_url(inbox)}/webhooks/#{subscription_name_for(inbox)}"
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

  def reset_cache!
    @legacy_inbox_ids = nil
  end

  # === Legacy (env var) fallbacks ===

  def legacy_inbox_ids
    @legacy_inbox_ids ||= ENV.fetch('CAPTAIN_HERMES_INBOX_IDS', '')
                             .split(',')
                             .map { |s| s.strip.to_i }
                             .reject(&:zero?)
                             .freeze
  end

  def legacy_webhook_base_url(inbox = nil)
    if inbox && (per_inbox = ENV.fetch("CAPTAIN_HERMES_BASE_URL_INBOX_#{inbox.id}", nil)).present?
      return per_inbox.chomp('/')
    end

    (ENV['CAPTAIN_HERMES_WEBHOOK_BASE_URL'].presence || DEFAULT_BASE_URL).chomp('/')
  end
end
