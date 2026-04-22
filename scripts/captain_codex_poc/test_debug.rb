#!/usr/bin/env ruby
# Debug: imprime os eventos SSE crus pra entender o formato exato que a Codex API devolve.

require 'net/http'
require 'uri'
require 'json'
require_relative 'codex_client'

tokens = JSON.parse(File.read(CodexPoc::TOKENS_PATH))
access_token = tokens.fetch('access_token')

uri = URI("#{CodexPoc::API_BASE}/responses")
body = {
  model: 'gpt-5.4',
  input: [{ role: 'user', content: 'Diga em uma frase curta: qual a capital do Brasil?' }],
  instructions: 'Seja breve.',
  store: false,
  stream: true
}

Net::HTTP.start(uri.host, uri.port, use_ssl: true, read_timeout: 60) do |http|
  req = Net::HTTP::Post.new(uri)
  req['Content-Type'] = 'application/json'
  req['Authorization'] = "Bearer #{access_token}"
  req['Accept'] = 'text/event-stream'
  req.body = JSON.generate(body)

  http.request(req) do |resp|
    puts "Status: #{resp.code}"
    if resp.code.to_i != 200
      err = +''
      resp.read_body { |c| err << c }
      puts "Erro: #{err}"
      exit 1
    end

    buffer = +''
    resp.read_body do |chunk|
      buffer << chunk
      while (idx = buffer.index("\n\n"))
        event = buffer.slice!(0, idx + 2)
        puts '--- SSE EVENT ---'
        puts event
      end
    end
    puts '--- FIM (buffer remanescente) ---'
    puts buffer
  end
end
