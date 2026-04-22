require 'net/http'

# Faz chamadas à Responses API do OpenAI Codex (via ChatGPT Plus OAuth).
#
# Uso:
#   body = Captain::Codex::Translator.chat_to_responses(chat_body)
#   aggregated = Captain::Codex::Client.new.responses(body)
#   chat_resp = Captain::Codex::Translator.responses_to_chat(aggregated)
#
# O cliente sempre faz streaming (exigência do endpoint Codex) e agrega
# os eventos SSE em um response final no mesmo formato do /responses síncrono.
class Captain::Codex::Client
  API_BASE = 'https://chatgpt.com/backend-api/codex'.freeze
  MAX_RETRIES = 2
  RETRY_DELAYS = [0.5, 1.5].freeze # segundos, backoff crescente

  class Error < StandardError
    attr_reader :http_status

    def initialize(message, http_status: nil)
      super(message)
      @http_status = http_status
    end
  end

  def responses(body)
    attempt = 0
    begin
      attempt += 1
      call_responses(body)
    rescue Error => e
      if retryable?(e) && attempt <= MAX_RETRIES
        sleep_time = RETRY_DELAYS[attempt - 1] || RETRY_DELAYS.last
        Rails.logger.warn("[Captain::Codex::Client] Retry #{attempt}/#{MAX_RETRIES} after #{sleep_time}s: #{e.message[0, 200]}")
        sleep sleep_time
        retry
      end
      raise
    end
  end

  private

  def call_responses(body)
    access_token = Captain::Codex::AuthService.valid_access_token
    state = { items: [], usage: nil, id: nil, model: nil, completed: false, error: nil }

    stream_post(access_token, body) { |event, data| handle_event(event, data, state) }

    raise transient_error("Stream failed: #{state[:error].inspect[0, 500]}") if state[:error]
    raise Error, 'Stream finished without response.completed' unless state[:completed]

    { 'id' => state[:id], 'model' => state[:model], 'output' => state[:items], 'usage' => state[:usage] }
  end

  def transient_error(message)
    Error.new(message, http_status: 503)
  end

  # Retry apenas em erros transitórios: server_error upstream ou HTTP 5xx.
  # Não retenta erros de auth (401/403) ou de validação (400).
  def retryable?(error)
    return true if error.http_status && error.http_status >= 500
    return true if error.message.include?('server_error')
    return true if error.message.include?('Stream finished without response.completed')

    false
  end

  def handle_event(event, data, state)
    case event
    when 'response.created'
      state[:id] = data.dig('response', 'id')
      state[:model] = data.dig('response', 'model')
    when 'response.output_item.done'
      state[:items] << data['item'] if data['item']
    when 'response.completed'
      state[:usage] = data.dig('response', 'usage')
      state[:model] ||= data.dig('response', 'model')
      state[:completed] = true
    when 'response.failed', 'error'
      state[:error] = data
    end
  end

  # Abre streaming pro Codex. Chama o bloco com (event_name, data_hash).
  def stream_post(access_token, body, &)
    uri = URI("#{API_BASE}/responses")

    Net::HTTP.start(uri.host, uri.port, use_ssl: true, read_timeout: 120) do |http|
      req = build_request(uri, access_token, body)
      http.request(req) { |resp| consume_stream(resp, &) }
    end
  end

  def build_request(uri, access_token, body)
    req = Net::HTTP::Post.new(uri)
    req['Content-Type'] = 'application/json'
    req['Authorization'] = "Bearer #{access_token}"
    req['Accept'] = 'text/event-stream'
    req.body = JSON.generate(body)
    req
  end

  def consume_stream(resp)
    unless resp.is_a?(Net::HTTPSuccess)
      err_body = +''
      resp.read_body { |chunk| err_body << chunk }
      raise Error.new("HTTP #{resp.code}: #{err_body[0, 800]}", http_status: resp.code.to_i)
    end

    buffer = +''
    resp.read_body do |chunk|
      buffer << chunk
      while (idx = buffer.index("\n\n"))
        raw_event = buffer.slice!(0, idx + 2)
        parsed = parse_sse_event(raw_event)
        yield(parsed[:event], parsed[:data]) if parsed
      end
    end
  end

  def parse_sse_event(raw)
    event_name, data_lines = parse_sse_lines(raw)
    return nil if data_lines.empty?

    data_str = data_lines.join("\n")
    return nil if data_str == '[DONE]'

    parsed = safe_json_parse(data_str)
    return nil unless parsed

    { event: event_name || parsed['type'] || 'message', data: parsed }
  end

  def parse_sse_lines(raw)
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
    [event_name, data_lines]
  end

  def safe_json_parse(str)
    JSON.parse(str)
  rescue JSON::ParserError
    nil
  end
end
