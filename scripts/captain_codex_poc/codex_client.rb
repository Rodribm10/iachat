require 'net/http'
require 'uri'
require 'json'
require 'time'

module CodexPoc
  CLIENT_ID = 'app_EMoamEEZ73f0CkXaXp7hrann'.freeze
  ISSUER = 'https://auth.openai.com'.freeze
  TOKEN_URL = "#{ISSUER}/oauth/token".freeze
  API_BASE = 'https://chatgpt.com/backend-api/codex'.freeze
  TOKENS_PATH = File.expand_path('tokens.json', __dir__).freeze
  REFRESH_SKEW_SECONDS = 120

  class Error < StandardError; end

  class Client
    def initialize
      load_tokens!
    end

    # Chama a Responses API do Codex em modo streaming (obrigatório nesse endpoint).
    # Agrega o texto e tool_calls dos eventos SSE e retorna como objeto consolidado.
    def responses(model:, system_prompt: nil, user_messages:, tools: nil, max_tokens: nil)
      refresh_if_expiring!

      input = user_messages.is_a?(String) ? [{ role: 'user', content: user_messages }] : user_messages

      body = {
        model: model,
        input: input,
        store: false,
        stream: true
      }
      body[:instructions] = system_prompt if system_prompt
      body[:tools] = tools if tools
      body[:tool_choice] = 'auto' if tools
      body[:max_output_tokens] = max_tokens if max_tokens

      stream_responses("#{API_BASE}/responses", body)
    end

    # Extrai texto + tool_calls do output consolidado.
    def self.extract(resp)
      output = resp['output'] || []
      text_parts = []
      tool_calls = []

      output.each do |item|
        case item['type']
        when 'message'
          Array(item['content']).each do |part|
            text_parts << part['text'] if part['type'] == 'output_text' && part['text']
          end
        when 'function_call'
          tool_calls << {
            name: item['name'],
            arguments: item['arguments'],
            call_id: item['call_id'] || item['id']
          }
        end
      end

      { text: text_parts.join("\n"), tool_calls: tool_calls, raw_output: output }
    end

    private

    def load_tokens!
      unless File.exist?(TOKENS_PATH)
        raise Error, "Tokens não encontrados em #{TOKENS_PATH}. Rode primeiro: ruby scripts/captain_codex_poc/login.rb"
      end
      data = JSON.parse(File.read(TOKENS_PATH))
      @access_token = data.fetch('access_token')
      @refresh_token = data.fetch('refresh_token')
      @expires_at = data['expires_at'] ? Time.parse(data['expires_at']) : nil
    end

    def refresh_if_expiring!
      return unless @expires_at
      return if Time.now < @expires_at - REFRESH_SKEW_SECONDS

      puts "[codex_client] Refrescando token (expira em #{@expires_at})..."
      resp = post_form(TOKEN_URL, {
        grant_type: 'refresh_token',
        refresh_token: @refresh_token,
        client_id: CLIENT_ID
      })

      @access_token = resp.fetch('access_token')
      @refresh_token = resp['refresh_token'] || @refresh_token
      @expires_at = Time.now + Integer(resp['expires_in'] || 3600)
      persist_tokens!
    end

    def persist_tokens!
      File.write(TOKENS_PATH, JSON.pretty_generate({
        access_token: @access_token,
        refresh_token: @refresh_token,
        expires_at: @expires_at.iso8601
      }))
    end

    # Consome o stream SSE da Responses API.
    # Agrega os items finalizados (output_item.done) + o usage do response.completed.
    # Retorna { "output" => [...items...], "usage" => {...} }
    def stream_responses(url, body)
      uri = URI(url)
      items = []
      usage = nil
      completed = false
      final_error = nil

      Net::HTTP.start(uri.host, uri.port, use_ssl: true, read_timeout: 120) do |http|
        req = Net::HTTP::Post.new(uri)
        req['Content-Type'] = 'application/json'
        req['Authorization'] = "Bearer #{@access_token}"
        req['Accept'] = 'text/event-stream'
        req.body = JSON.generate(body)

        http.request(req) do |resp|
          unless resp.is_a?(Net::HTTPSuccess)
            err_body = +''
            resp.read_body { |chunk| err_body << chunk }
            raise Error, "HTTP #{resp.code} em #{url}: #{err_body[0, 800]}"
          end

          buffer = +''
          resp.read_body do |chunk|
            buffer << chunk
            while (idx = buffer.index("\n\n"))
              event = buffer.slice!(0, idx + 2)
              parsed = parse_sse_event(event)
              next unless parsed

              case parsed[:event]
              when 'response.output_item.done'
                items << parsed[:data]['item'] if parsed[:data]['item']
              when 'response.completed'
                usage = parsed[:data].dig('response', 'usage')
                completed = true
              when 'response.failed', 'error'
                final_error = parsed[:data]
              end
            end
          end
        end
      end

      raise Error, "Stream falhou: #{final_error.inspect[0, 500]}" if final_error
      raise Error, 'Stream terminou sem response.completed' unless completed

      { 'output' => items, 'usage' => usage }
    end

    # Parseia um bloco SSE ("event: foo\ndata: {...}\n\n")
    def parse_sse_event(raw)
      event_name = nil
      data_lines = []
      raw.each_line do |line|
        line = line.chomp
        next if line.empty?
        if line.start_with?('event:')
          event_name = line.sub('event:', '').strip
        elsif line.start_with?('data:')
          data_lines << line.sub('data:', '').strip
        end
      end
      return nil if data_lines.empty?
      data_str = data_lines.join("\n")
      return nil if data_str == '[DONE]'
      parsed = JSON.parse(data_str) rescue nil
      return nil unless parsed
      { event: event_name || parsed['type'] || 'message', data: parsed }
    end

    def post_form(url, params)
      uri = URI(url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.read_timeout = 30

      req = Net::HTTP::Post.new(uri)
      req['Content-Type'] = 'application/x-www-form-urlencoded'
      req.body = URI.encode_www_form(params)

      resp = http.request(req)
      unless resp.is_a?(Net::HTTPSuccess)
        raise Error, "HTTP #{resp.code} em #{url}: #{resp.body}"
      end
      JSON.parse(resp.body)
    end
  end
end
