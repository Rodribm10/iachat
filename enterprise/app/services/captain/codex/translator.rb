# Traduz payloads entre os formatos:
#   OpenAI Chat Completions (legado, o que o Captain usa)
#   OpenAI Responses API (o que o endpoint ChatGPT Plus Codex exige)
#
# Opera em cima de hashes — sem I/O. I/O fica no Client.
class Captain::Codex::Translator
  # Permite forçar um modelo diferente no proxy via CAPTAIN_CODEX_MODEL_OVERRIDE.
  # Útil pra usar modelos que o RubyLLM ainda não reconhece no catalog
  # (ex: gpt-5.4, gpt-5.3-codex) — o Captain continua mandando gpt-5.2
  # (validado pelo RubyLLM) e o proxy substitui antes de chegar no Codex.
  def self.override_model(requested)
    override = InstallationConfig.find_by(name: 'CAPTAIN_CODEX_MODEL_OVERRIDE')&.value.presence
    override || requested
  end

  # --- Request: chat completions → responses ---

  # chat_body: hash no formato OpenAI Chat Completions.
  # Retorna hash pro POST /responses.
  def self.chat_to_responses(chat_body)
    messages = chat_body['messages'] || chat_body[:messages] || []
    instructions, input = split_system(messages)

    body = {
      model: override_model(chat_body['model'] || chat_body[:model]),
      input: input,
      # Codex exige o campo instructions sempre. Se não vier system message,
      # usamos uma string com um espaço pra satisfazer o endpoint sem influenciar o comportamento.
      instructions: instructions.presence || ' ',
      store: false,
      stream: true # Codex exige streaming sempre — o Client agrega.
    }
    body[:max_output_tokens] = chat_body['max_tokens'] if chat_body['max_tokens']

    tools = chat_body['tools'] || chat_body[:tools]
    if tools.present?
      body[:tools] = tools.map { |t| translate_tool(t) }
      body[:tool_choice] = translate_tool_choice(chat_body['tool_choice'] || chat_body[:tool_choice])
    end

    body
  end

  # Separa a(s) mensagem(ns) system do resto.
  # Várias system messages viram uma única instruction com \n\n.
  def self.split_system(messages)
    systems = []
    input = []

    messages.each do |raw|
      msg = raw.stringify_keys
      translate_message(msg, systems: systems, input: input)
    end

    [systems.any? ? systems.join("\n\n") : nil, input]
  end

  def self.translate_message(msg, systems:, input:)
    case msg['role']
    when 'system'
      systems << stringify_content(msg['content'])
    when 'tool'
      input << translate_tool_result(msg)
    when 'assistant'
      translate_assistant_message(msg, input)
    else
      input << { role: msg['role'], content: stringify_content(msg['content']) }
    end
  end

  def self.translate_tool_result(msg)
    {
      type: 'function_call_output',
      call_id: msg['tool_call_id'],
      output: stringify_content(msg['content'])
    }
  end

  def self.translate_assistant_message(msg, input)
    tool_calls = msg['tool_calls']
    if tool_calls.present?
      tool_calls.each { |tc| input << translate_historical_tool_call(tc) }
      input << { role: 'assistant', content: stringify_content(msg['content']) } if msg['content'].present?
    else
      input << { role: 'assistant', content: stringify_content(msg['content']) }
    end
  end

  def self.translate_historical_tool_call(tool_call)
    fn = tool_call['function'] || {}
    {
      type: 'function_call',
      call_id: tool_call['id'],
      name: fn['name'],
      arguments: fn['arguments']
    }
  end

  # Chat: { type: "function", function: { name, description, parameters } }
  # Responses: { type: "function", name, description, parameters, strict }
  def self.translate_tool(tool)
    tool = tool.stringify_keys
    fn = (tool['function'] || {}).stringify_keys
    {
      type: 'function',
      name: fn['name'],
      description: fn['description'],
      parameters: fn['parameters'] || { type: 'object', properties: {} },
      strict: fn['strict'] || false
    }.compact
  end

  def self.translate_tool_choice(choice)
    return 'auto' if choice.nil?
    return choice if choice.is_a?(String) # auto, none, required

    if choice.is_a?(Hash)
      choice = choice.stringify_keys
      return { type: 'function', name: choice.dig('function', 'name') } if choice['type'] == 'function'
    end

    'auto'
  end

  def self.stringify_content(content)
    return '' if content.nil?
    return content if content.is_a?(String)
    return content.map { |part| part.is_a?(Hash) ? (part['text'] || part[:text]) : part.to_s }.join("\n") if content.is_a?(Array)

    content.to_s
  end

  # --- Response: responses (agregado) → chat completions ---

  # aggregated: { "output" => [items...], "usage" => {...}, "id" => "resp_...", "model" => "..." }
  # Retorna hash formato Chat Completions.
  def self.responses_to_chat(aggregated)
    text_parts, tool_calls = extract_output(aggregated['output'] || [])
    message = build_assistant_message(text_parts, tool_calls)

    {
      id: aggregated['id'] || "chatcmpl-#{SecureRandom.hex(12)}",
      object: 'chat.completion',
      created: Time.current.to_i,
      model: aggregated['model'],
      choices: [{ index: 0, message: message, finish_reason: tool_calls.any? ? 'tool_calls' : 'stop' }],
      usage: translate_usage(aggregated['usage'])
    }
  end

  def self.extract_output(items)
    text_parts = []
    tool_calls = []

    items.each do |item|
      case item['type']
      when 'message'
        Array(item['content']).each do |part|
          text_parts << part['text'] if part['type'] == 'output_text' && part['text']
        end
      when 'function_call'
        tool_calls << {
          id: item['call_id'] || item['id'],
          type: 'function',
          function: { name: item['name'], arguments: item['arguments'] || '{}' }
        }
      end
    end

    [text_parts, tool_calls]
  end

  def self.build_assistant_message(text_parts, tool_calls)
    message = { role: 'assistant' }
    message[:content] = text_parts.any? ? text_parts.join("\n") : nil
    message[:tool_calls] = tool_calls if tool_calls.any?
    message
  end

  # Codex usage: { input_tokens, output_tokens, total_tokens }
  # Chat usage: { prompt_tokens, completion_tokens, total_tokens }
  def self.translate_usage(usage)
    return nil if usage.nil?

    usage = usage.stringify_keys
    {
      prompt_tokens: usage['input_tokens'] || 0,
      completion_tokens: usage['output_tokens'] || 0,
      total_tokens: usage['total_tokens'] || 0
    }
  end
end
