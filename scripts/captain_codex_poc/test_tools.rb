#!/usr/bin/env ruby
# Go/no-go crítico: function calling via /responses.

require_relative 'codex_client'

# Formato Responses API: tools sem wrapping `function: {...}`
TOOLS = [
  {
    type: 'function',
    name: 'gerar_pix',
    description: 'Gera um Pix para pagamento de reserva de hotel. Use apenas após ter CPF e nome do hóspede.',
    strict: false,
    parameters: {
      type: 'object',
      properties: {
        cpf: { type: 'string', description: 'CPF do hóspede, apenas dígitos' },
        nome: { type: 'string', description: 'Nome completo do hóspede' },
        valor: { type: 'number', description: 'Valor em reais' },
        descricao: { type: 'string', description: 'Descrição da reserva' }
      },
      required: %w[cpf nome valor descricao]
    }
  }
].freeze

SYSTEM = 'Você é um recepcionista de hotel. Quando tiver CPF e nome do hóspede, chame a tool gerar_pix para emitir o pagamento. Nunca invente dados.'.freeze
USER = 'Oi, quero fechar a reserva. Meu nome é Rodrigo Borba Machado, CPF 123.456.789-00. O valor era R$ 320 por uma diária no Prime.'.freeze

MODELS_TO_TRY = %w[gpt-5.4 gpt-5.4-mini gpt-5.2 gpt-5.3-codex].freeze

client = CodexPoc::Client.new

MODELS_TO_TRY.each do |model|
  puts "=== Function calling — modelo: #{model} ==="
  begin
    resp = client.responses(
      model: model,
      system_prompt: SYSTEM,
      user_messages: USER,
      tools: TOOLS
    )

    out = CodexPoc::Client.extract(resp)

    if out[:tool_calls].empty?
      warn "[FAIL] #{model} NÃO chamou a tool. Texto retornado:"
      warn "       #{out[:text][0, 400]}"
    else
      call = out[:tool_calls].first
      begin
        args = JSON.parse(call[:arguments])
        puts "[PASS] #{model} chamou tool '#{call[:name]}' com args:"
        puts JSON.pretty_generate(args)
      rescue JSON::ParserError => e
        warn "[FAIL] #{model} chamou tool mas args não são JSON: #{call[:arguments].inspect} (#{e.message})"
      end
    end
    puts
  rescue CodexPoc::Error => e
    warn "FALHOU para #{model}: #{e.message[0, 300]}"
    puts
  end
end

puts '=== Fim do teste de function calling ==='
puts 'GO/NO-GO: se ao menos gpt-5.4 (ou gpt-5.3-codex) passou com args JSON válidos, seguimos.'
