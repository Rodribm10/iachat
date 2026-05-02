# Storage de mensagens da UI Hermes Builder.
#
# Persistência em Rails.cache (Redis em prod) — TTL 4h. Suficiente pra uma
# sessão de criação completa de agente (geralmente ~10-20min).
#
# Cada mensagem tem: role ('user' | 'construtor'), content (string),
# created_at (ISO8601). Lista cresce em ordem cronológica.
module HermesBuilder
end

module HermesBuilder::Storage
  TTL = 4.hours
  MAX_MESSAGES = 200

  module_function

  def messages_for(session_key)
    Rails.cache.fetch(session_key) { [] }
  end

  def append(session_key, role:, content:)
    msgs = messages_for(session_key)
    msgs << { role: role, content: content.to_s, created_at: Time.current.iso8601 }
    msgs = msgs.last(MAX_MESSAGES)
    Rails.cache.write(session_key, msgs, expires_in: TTL)
    msgs
  end

  def clear(session_key)
    Rails.cache.delete(session_key)
  end

  # Última sessão ativa por account — usada pelo callback do Hermes pra
  # roteamento (Hermes nao propaga chat_id no metadata da resposta).
  # Aceitavel pra MVP com 1 admin por vez por conta.
  def remember_last_session(account_id, session_key)
    Rails.cache.write("hermes_builder:last_session:account:#{account_id}", session_key, expires_in: TTL)
  end

  def last_session_for(account_id)
    Rails.cache.read("hermes_builder:last_session:account:#{account_id}")
  end
end
