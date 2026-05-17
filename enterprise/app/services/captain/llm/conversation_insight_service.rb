class Captain::Llm::ConversationInsightService < Llm::BaseAiService
  include Integrations::LlmInstrumentation

  MAX_CHARS_PER_CHUNK = 40_000

  def initialize(account:, conversations:, unit: nil, inbox: nil, period_start: nil, period_end: nil)
    super()
    @account = account
    @unit = unit
    @inbox = inbox
    @conversations = conversations
    @period_start = period_start
    @period_end = period_end
  end

  # Analisa as conversas e retorna o payload de insights
  def analyze
    chunks = build_chunks
    return empty_payload if chunks.empty?

    results = chunks.filter_map { |chunk| analyze_chunk(chunk) }
    return empty_payload if results.empty?

    merge_results(results)
  end

  private

  attr_reader :account, :unit, :inbox, :conversations, :period_start, :period_end

  def build_chunks
    texts = conversations.map { |conversation| conversation_text(conversation) }.reject(&:blank?)
    return [] if texts.empty?

    chunks = []
    current = []
    current_size = 0

    texts.each do |text|
      if current_size + text.length > MAX_CHARS_PER_CHUNK && current.any?
        chunks << current.join("\n\n---\n\n")
        current = []
        current_size = 0
      end
      current << text
      current_size += text.length
    end

    chunks << current.join("\n\n---\n\n") if current.any?
    chunks
  end

  def conversation_text(conversation)
    return conversation.to_llm_text unless period_start && period_end

    messages = conversation.messages
                           .where(created_at: period_start.beginning_of_day..period_end.end_of_day)
                           .where.not(message_type: %i[activity template])
                           .where(private: false)
                           .order(created_at: :asc)

    return nil if messages.empty?

    [
      "Conversation ID: ##{conversation.display_id}",
      "Channel: #{conversation.inbox.channel.name}",
      'Message History:',
      messages.map { |message| format_message(message) }.join
    ].join("\n")
  end

  def format_message(message)
    sender = case message.sender_type
             when 'User'
               'Support Agent'
             when 'Contact'
               'User'
             else
               'Bot'
             end

    "#{sender}: #{message.content_for_llm}\n"
  end

  def analyze_chunk(chunk)
    response = instrument_llm_call(instrumentation_params) do
      chat
        .with_params(response_format: { type: 'json_object' })
        .with_instructions(system_prompt)
        .ask(chunk)
    end

    parse_response(response.content)
  rescue RubyLLM::Error => e
    Rails.logger.error "[Captain::Llm::ConversationInsightService] LLM Error: #{e.message}"
    nil
  end

  def system_prompt
    entity_name = inbox&.name || unit&.name || 'Geral'
    Captain::Llm::SystemPromptsService.conversation_insights_analyzer(
      entity_name,
      account.locale_english_name
    )
  end

  def instrumentation_params
    {
      span_name: 'llm.captain.conversation_insights',
      model: @model,
      temperature: @temperature,
      feature_name: 'conversation_insights',
      account_id: account.id,
      messages: [{ role: 'system', content: system_prompt }]
    }
  end

  def merge_results(results)
    base = results.first.dup

    results.drop(1).each do |result|
      merge_arrays!(base, result)
      merge_sentiment!(base, result)
      merge_highlights!(base, result)
      base['recommendations'] = ((base['recommendations'] || []) + (result['recommendations'] || [])).uniq
    end

    base
  end

  def merge_arrays!(base, result)
    base['top_topics'] = merge_by_topic(base['top_topics'], result['top_topics'])
    base['ai_failures'] = merge_by_description(base['ai_failures'], result['ai_failures'])
    base['faq_gaps'] = merge_by_question(base['faq_gaps'], result['faq_gaps'])
    base['most_requested_suites'] = merge_by_suite(base['most_requested_suites'], result['most_requested_suites'])
    base['customer_opportunities'] = merge_by_opportunity(base['customer_opportunities'], result['customer_opportunities'])
  end

  def merge_sentiment!(base, result)
    %w[positive_count negative_count neutral_count].each do |key|
      base['sentiment'][key] = base.dig('sentiment', key).to_i + result.dig('sentiment', key).to_i
    end
  end

  def merge_highlights!(base, result)
    %w[praises complaints].each do |key|
      base['highlights'][key] = (base.dig('highlights', key) || []) + (result.dig('highlights', key) || [])
    end
  end

  def merge_by_topic(arr_a, arr_b)
    merge_arrays_by_key(arr_a, arr_b, 'topic', 'count')
  end

  def merge_by_description(arr_a, arr_b)
    merge_arrays_by_key(arr_a, arr_b, 'description', 'frequency')
  end

  def merge_by_question(arr_a, arr_b)
    merge_arrays_by_key(arr_a, arr_b, 'question', 'frequency')
  end

  def merge_by_suite(arr_a, arr_b)
    merge_arrays_by_key(arr_a, arr_b, 'suite', 'count')
  end

  def merge_by_opportunity(arr_a, arr_b)
    merge_arrays_by_key(arr_a, arr_b, 'opportunity', 'frequency')
  end

  def merge_arrays_by_key(arr_a, arr_b, label_key, count_key)
    merged = ((arr_a || []) + (arr_b || [])).group_by { |item| item[label_key] }
    merged
      .map { |_label, items| items.first.merge(count_key => items.sum { |i| i[count_key].to_i }) }
      .sort_by { |item| -item[count_key].to_i }
      .take(10)
  end

  def parse_response(content)
    return nil if content.nil?

    JSON.parse(content.strip)
  rescue JSON::ParserError => e
    Rails.logger.error "[Captain::Llm::ConversationInsightService] JSON parse error: #{e.message}"
    nil
  end

  def empty_payload
    {
      'top_topics' => [],
      'ai_failures' => [],
      'faq_gaps' => [],
      'sentiment' => { 'positive_count' => 0, 'negative_count' => 0, 'neutral_count' => 0, 'summary' => '' },
      'highlights' => { 'praises' => [], 'complaints' => [] },
      'most_requested_suites' => [],
      'price_reactions' => { 'summary' => '', 'objections_count' => 0 },
      'customer_opportunities' => [],
      'recommendations' => [],
      'period_summary' => 'Sem conversas suficientes para análise no período.'
    }
  end
end
