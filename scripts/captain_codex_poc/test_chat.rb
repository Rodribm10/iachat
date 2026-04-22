#!/usr/bin/env ruby
# Smoke test: /responses com vários modelos via Codex OAuth.

require_relative 'codex_client'

# Testa modelos na ordem do que o Rodrigo quer (gpt-5.4 primeiro).
# Inclui gpt-5.3-codex porque é o que o Hermes usa com sucesso.
MODELS_TO_TRY = %w[gpt-5.4 gpt-5.4-mini gpt-5.2 gpt-5.3-codex].freeze

client = CodexPoc::Client.new

MODELS_TO_TRY.each do |model|
  puts "=== Testando modelo: #{model} ==="
  begin
    resp = client.responses(
      model: model,
      system_prompt: 'Você é um recepcionista dos Hoteis 1001 Noites. Responda em português do Brasil, de forma breve e direta.',
      user_messages: 'Oi, boa tarde. Queria saber se tem diária disponível para esse fim de semana.'
    )

    out = CodexPoc::Client.extract(resp)
    puts "Resposta: #{out[:text]}"
    puts "Usage: #{resp['usage']}"
    puts
  rescue CodexPoc::Error => e
    warn "FALHOU para #{model}: #{e.message[0, 300]}"
    puts
  end
end

puts '=== Fim do teste de chat ==='
