#!/usr/bin/env ruby
# Qualidade conversacional: simula a Jasmine via /responses.

require_relative 'codex_client'

JASMINE_SYSTEM = <<~PROMPT.freeze
  Você é a Jasmine, recepcionista dos Hoteis 1001 Noites. Atende no WhatsApp.

  Regras:
  - Sempre em português do Brasil, tom acolhedor mas direto, frases curtas
  - Se souber o nome do cliente, SEMPRE começa com "Oi, {primeiro_nome}!"
  - Nunca invente preços, diárias ou disponibilidade — se não souber, diga que vai verificar
  - Identifique o cenário em 1-2 mensagens: pré-reserva, check-in, reclamação, dúvida geral
  - Se for pré-reserva, colete: datas, número de hóspedes, tipo de quarto, forma de pagamento

  Unidades:
  - 1001 Noites Prime (Brasília)
  - 1001 Noites Express (Águas Lindas)
  - Dolce Amore (Natal)
PROMPT

SCENARIOS = [
  {
    name: 'Pré-reserva com nome',
    contact_name: 'Rodrigo Borba Machado',
    user: 'Oi, boa tarde. Queria ver uma diária para esse fim de semana'
  },
  {
    name: 'Cliente anônimo',
    contact_name: nil,
    user: 'vcs tem quarto pra essa sexta?'
  },
  {
    name: 'Reclamação',
    contact_name: 'Maria Silva',
    user: 'Acabei de sair do hotel e o ar condicionado não funcionou a noite toda. Paguei R$400 por noite, isso é uma falta de respeito.'
  }
].freeze

MODEL = ENV.fetch('CODEX_MODEL', 'gpt-5.4')

client = CodexPoc::Client.new
puts "Modelo: #{MODEL}\n\n"

SCENARIOS.each do |scenario|
  puts "=== #{scenario[:name]} ==="
  puts "Contato: #{scenario[:contact_name] || '(desconhecido)'}"
  puts "Cliente: #{scenario[:user]}"
  puts

  system_prompt = JASMINE_SYSTEM.dup
  system_prompt += "\n\nDados do contato: nome = #{scenario[:contact_name]}." if scenario[:contact_name]

  begin
    resp = client.responses(
      model: MODEL,
      system_prompt: system_prompt,
      user_messages: scenario[:user]
    )
    out = CodexPoc::Client.extract(resp)
    puts "Jasmine: #{out[:text]}"
  rescue CodexPoc::Error => e
    warn "FALHOU: #{e.message[0, 300]}"
  end
  puts "\n---\n\n"
end
