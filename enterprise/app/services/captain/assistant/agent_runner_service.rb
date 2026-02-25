require 'agents'
require 'agents/instrumentation'
require 'json'

class Captain::Assistant::AgentRunnerService
  include Integrations::LlmInstrumentationConstants

  FAQ_UNCERTAINTY_PATTERNS = [
    /\bnao (sei|tenho|consigo|possuo)\b/i,
    /\bi do not (know|have access)\b/i,
    /\bi don't (know|have|have access)\b/i,
    /\bcan'?t (access|help|provide)\b/i
  ].freeze
  FAQ_PRICE_PATTERNS = [
    /r\$\s*\d+/i,
    /\b\d+[,.]?\d*\s*(reais|real)\b/i,
    /\b(preco|preço|valor|diaria|diária|pernoite|sinal)\b/i
  ].freeze
  FAQ_NOT_FOUND_FALLBACK = 'Consultei o FAQ e não encontrei essa informação cadastrada ainda. Posso te ajudar com outro tema ou te transferir para um atendente.'.freeze

  CONVERSATION_STATE_ATTRIBUTES = %i[
    id display_id inbox_id contact_id status priority
    label_list custom_attributes additional_attributes
  ].freeze

  CONTACT_STATE_ATTRIBUTES = %i[
    id name email phone_number identifier contact_type
    custom_attributes additional_attributes
  ].freeze

  def initialize(assistant:, conversation: nil, callbacks: {})
    @assistant = assistant
    @conversation = conversation
    @callbacks = callbacks
  end

  def generate_response(message_history: [])
    agents = build_and_wire_agents
    context = build_context(message_history)
    message_to_process = extract_last_user_message(message_history)
    runner = Agents::Runner.with_agents(*agents)
    runner = add_usage_metadata_callback(runner)
    runner = add_callbacks_to_runner(runner) if @callbacks.any?
    install_instrumentation(runner)
    result = runner.run(message_to_process, context: context, max_turns: 100)

    process_agent_result(result, original_query: message_to_process)
  rescue StandardError => e
    # when running the agent runner service in a rake task, the conversation might not have an account associated
    # for regular production usage, it will run just fine
    ChatwootExceptionTracker.new(e, account: @conversation&.account).capture_exception
    Rails.logger.error "[Captain V2] AgentRunnerService error: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")

    error_response(e.message)
  end

  private

  def build_context(message_history)
    conversation_history = message_history.map do |msg|
      content = extract_text_from_content(msg[:content])

      {
        role: msg[:role].to_sym,
        content: content,
        # AgentRunner selects the starting agent from the last assistant message
        # with `agent_name` in conversation_history. We always want each turn to
        # start from the orchestrator and let it decide whether to handoff again.
        agent_name: nil
      }
    end

    {
      session_id: "#{@assistant.account_id}_#{@conversation&.display_id}",
      # Always start each turn from the orchestrator agent so factual questions
      # don't remain trapped inside a previously active scenario agent.
      current_agent: assistant_agent_name,
      conversation_history: conversation_history,
      state: build_state
    }
  end

  def assistant_agent_name
    @assistant.name.to_s.parameterize(separator: '_')
  end

  def extract_last_user_message(message_history)
    last_user_msg = message_history.reverse.find { |msg| msg[:role] == 'user' }

    extract_text_from_content(last_user_msg[:content], as_string: true)
  end

  def extract_text_from_content(content, as_string: false)
    raw_content = content.is_a?(RubyLLM::Content::Raw) ? content.value : content

    # Handle structured output from agents
    return raw_content[:response] || raw_content['response'] || raw_content.to_s if raw_content.is_a?(Hash)

    return raw_content unless raw_content.is_a?(Array)

    if as_string
      text_parts = raw_content.select { |part| part[:type] == 'text' }.pluck(:text)
      text_parts.join(' ')
    else
      content
    end
  end

  # Response formatting methods
  def process_agent_result(result, original_query:)
    Rails.logger.info "[Captain V2] Agent result: #{result.inspect}"
    response = format_response(result.output)

    # Extract agent name from context
    response['agent_name'] = result.context&.dig(:current_agent)
    enforce_faq_guardrail(response, result, original_query: original_query)
  end

  def enforce_faq_guardrail(response, result, original_query:)
    return response unless faq_feature_enabled?
    return response if response['response'] == 'conversation_handoff'

    guardrail_reason = faq_guardrail_reason(response['response'])
    return response if guardrail_reason.blank?
    return response if faq_lookup_called?(result, original_query: original_query)
    return response if original_query.blank?

    fallback_answer = faq_fallback_answer(original_query, response_text: response['response'])
    Rails.logger.warn("[Captain V2] FAQ guardrail triggered (#{guardrail_reason}) for query: #{original_query.inspect}")

    if fallback_answer.present?
      response['response'] = fallback_answer
      response['reasoning'] = "FAQ guardrail applied due to #{guardrail_reason} response without faq_lookup call."
    else
      response['response'] = FAQ_NOT_FOUND_FALLBACK
      response['reasoning'] = 'FAQ guardrail applied; no FAQ entry found for query.'
    end

    response
  end

  def faq_feature_enabled?
    ActiveModel::Type::Boolean.new.cast(@assistant.feature_faq)
  end

  def uncertainty_response?(text)
    normalized = I18n.transliterate(text.to_s).downcase
    FAQ_UNCERTAINTY_PATTERNS.any? { |pattern| normalized.match?(pattern) }
  end

  def price_response?(text)
    normalized = I18n.transliterate(text.to_s).downcase
    FAQ_PRICE_PATTERNS.any? { |pattern| normalized.match?(pattern) }
  end

  def faq_guardrail_reason(text)
    return 'uncertain' if uncertainty_response?(text)
    return 'price' if price_response?(text)

    nil
  end

  def faq_lookup_called?(result, original_query:)
    messages_for_current_turn(result, original_query).any? do |message|
      tool_calls = message[:tool_calls] || message['tool_calls'] || []
      Array(tool_calls).any? do |tool_call|
        tool_name = (tool_call[:name] || tool_call['name']).to_s
        tool_name.end_with?('faq_lookup')
      end
    end
  end

  def messages_for_current_turn(result, original_query)
    messages = Array(result.messages)
    return messages if messages.empty? || original_query.blank?

    normalized_query = original_query.to_s.strip
    last_user_index = messages.rindex do |message|
      role = (message[:role] || message['role']).to_s
      next false unless role == 'user'

      message_content = extract_text_from_content(message[:content] || message['content']).to_s.strip
      message_content == normalized_query
    end

    return messages unless last_user_index

    messages[(last_user_index + 1)..] || []
  end

  def faq_fallback_answer(query, response_text: nil)
    faq_query_candidates(query, response_text: response_text).each do |candidate|
      responses = @assistant.responses.approved.search(candidate).to_a
      Rails.logger.info "[Captain V2] FAQ guardrail fallback results=#{responses.size} query=#{candidate.inspect}"
      return responses.first&.answer if responses.present?
    end

    nil
  rescue StandardError => e
    Rails.logger.warn("[Captain V2] FAQ guardrail fallback failed: #{e.message}")
    nil
  end

  def faq_query_candidates(original_query, response_text: nil)
    candidates = [original_query.to_s]
    response_body = response_text.to_s
    candidates << response_body if response_body.present?

    suite_hint = response_body.match(/su[ií]te\s+([a-z0-9]+)/i)&.captures&.first
    candidates << "valor da suíte #{suite_hint}" if suite_hint.present?

    candidates.map(&:squish).reject(&:blank?).uniq
  end

  def format_response(output)
    return output.with_indifferent_access if output.is_a?(Hash)

    parsed_output = parse_structured_output_string(output.to_s)
    return parsed_output if parsed_output.present?

    # Fallback for backwards compatibility
    {
      'response' => output.to_s,
      'reasoning' => 'Processed by agent'
    }
  end

  def error_response(error_message)
    {
      'response' => 'conversation_handoff',
      'reasoning' => "Error occurred: #{error_message}"
    }
  end

  def parse_structured_output_string(output_text)
    return nil if output_text.blank?

    parsed_candidates = extract_json_objects(output_text).filter_map do |json_object|
      JSON.parse(json_object)
    rescue JSON::ParserError
      nil
    end

    candidate = parsed_candidates.reverse.find do |item|
      item.is_a?(Hash) && item['response'].present?
    end
    return nil unless candidate

    {
      'response' => candidate['response'].to_s,
      'reasoning' => candidate['reasoning'].presence || 'Processed by agent',
      'reaction_emoji' => candidate['reaction_emoji'].to_s
    }
  end

  def extract_json_objects(text)
    objects = []
    start_index = nil
    depth = 0
    in_string = false
    escaped = false

    text.each_char.with_index do |char, index|
      if in_string
        if escaped
          escaped = false
        elsif char == '\\'
          escaped = true
        elsif char == '"'
          in_string = false
        end
        next
      end

      if char == '"'
        in_string = true
      elsif char == '{'
        start_index = index if depth.zero?
        depth += 1
      elsif char == '}'
        next if depth.zero?

        depth -= 1
        if depth.zero? && start_index
          objects << text[start_index..index]
          start_index = nil
        end
      end
    end

    objects
  end

  def build_state
    state = {
      account_id: @assistant.account_id,
      assistant_id: @assistant.id,
      assistant_config: @assistant.config
    }

    if @conversation
      state[:conversation] = @conversation.attributes.symbolize_keys.slice(*CONVERSATION_STATE_ATTRIBUTES)
      state[:contact] = @conversation.contact.attributes.symbolize_keys.slice(*CONTACT_STATE_ATTRIBUTES) if @conversation.contact
    end

    state
  end

  def build_and_wire_agents
    assistant_agent = @assistant.agent
    scenario_agents = @assistant.scenarios.enabled.map(&:agent)

    assistant_agent.register_handoffs(*scenario_agents) if scenario_agents.any?
    scenario_agents.each { |scenario_agent| scenario_agent.register_handoffs(assistant_agent) }

    [assistant_agent] + scenario_agents
  end

  def install_instrumentation(runner)
    return unless ChatwootApp.otel_enabled?

    Agents::Instrumentation.install(
      runner,
      tracer: OpentelemetryConfig.tracer,
      trace_name: 'llm.captain_v2',
      span_attributes: {
        ATTR_LANGFUSE_TAGS => ['captain_v2'].to_json
      },
      attribute_provider: ->(context_wrapper) { dynamic_trace_attributes(context_wrapper) }
    )
  end

  def dynamic_trace_attributes(context_wrapper)
    state = context_wrapper&.context&.dig(:state) || {}
    conversation = state[:conversation] || {}
    {
      ATTR_LANGFUSE_USER_ID => state[:account_id],
      format(ATTR_LANGFUSE_METADATA, 'assistant_id') => state[:assistant_id],
      format(ATTR_LANGFUSE_METADATA, 'conversation_id') => conversation[:id],
      format(ATTR_LANGFUSE_METADATA, 'conversation_display_id') => conversation[:display_id]
    }.compact.transform_values(&:to_s)
  end

  def add_callbacks_to_runner(runner)
    runner = add_agent_thinking_callback(runner) if @callbacks[:on_agent_thinking]
    runner = add_tool_start_callback(runner) if @callbacks[:on_tool_start]
    runner = add_tool_complete_callback(runner) if @callbacks[:on_tool_complete]
    runner = add_agent_handoff_callback(runner) if @callbacks[:on_agent_handoff]
    runner
  end

  def add_usage_metadata_callback(runner)
    return runner unless ChatwootApp.otel_enabled?

    handoff_tool_name = Captain::Tools::HandoffTool.new(@assistant).name

    runner.on_tool_complete do |tool_name, _tool_result, context_wrapper|
      track_handoff_usage(tool_name, handoff_tool_name, context_wrapper)
    end

    runner.on_run_complete do |_agent_name, _result, context_wrapper|
      write_credits_used_metadata(context_wrapper)
    end
    runner
  end

  def track_handoff_usage(tool_name, handoff_tool_name, context_wrapper)
    return unless context_wrapper&.context
    return unless tool_name.to_s == handoff_tool_name

    context_wrapper.context[:captain_v2_handoff_tool_called] = true
  end

  def write_credits_used_metadata(context_wrapper)
    root_span = context_wrapper&.context&.dig(:__otel_tracing, :root_span)
    return unless root_span

    credit_used = !context_wrapper.context[:captain_v2_handoff_tool_called]
    root_span.set_attribute(format(ATTR_LANGFUSE_METADATA, 'credit_used'), credit_used.to_s)
  end

  def add_agent_thinking_callback(runner)
    runner.on_agent_thinking do |*args|
      @callbacks[:on_agent_thinking].call(*args)
    rescue StandardError => e
      Rails.logger.warn "[Captain] Callback error for agent_thinking: #{e.message}"
    end
  end

  def add_tool_start_callback(runner)
    runner.on_tool_start do |*args|
      @callbacks[:on_tool_start].call(*args)
    rescue StandardError => e
      Rails.logger.warn "[Captain] Callback error for tool_start: #{e.message}"
    end
  end

  def add_tool_complete_callback(runner)
    runner.on_tool_complete do |*args|
      @callbacks[:on_tool_complete].call(*args)
    rescue StandardError => e
      Rails.logger.warn "[Captain] Callback error for tool_complete: #{e.message}"
    end
  end

  def add_agent_handoff_callback(runner)
    runner.on_agent_handoff do |*args|
      @callbacks[:on_agent_handoff].call(*args)
    rescue StandardError => e
      Rails.logger.warn "[Captain] Callback error for agent_handoff: #{e.message}"
    end
  end
end
