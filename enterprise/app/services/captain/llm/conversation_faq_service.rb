class Captain::Llm::ConversationFaqService < Llm::BaseAiService
  include Integrations::LlmInstrumentation

  DISTANCE_THRESHOLD = 0.3
  MAX_JUDGE_NEIGHBOURS = 5

  def initialize(assistant, conversation)
    super()
    @assistant = assistant
    @conversation = conversation
    @content = conversation.to_llm_text
  end

  # Generates and deduplicates FAQs from conversation content
  # Skips processing if there was no human interaction
  def generate_and_deduplicate
    return [] if no_human_interaction?
    return [] unless human_answered_after_handoff?

    new_faqs = generate
    return [] if new_faqs.empty?

    duplicate_faqs, unique_faqs = find_and_separate_duplicates(new_faqs)
    save_new_faqs(unique_faqs)
    log_duplicate_faqs(duplicate_faqs) if Rails.env.development?
  end

  private

  attr_reader :content, :conversation, :assistant

  def no_human_interaction?
    conversation.first_reply_created_at.nil?
  end

  # A resposta humana só é conhecimento validado quando veio DEPOIS da triagem.
  # Conversa que foi para triagem, ninguém assumiu e morreu por inatividade
  # (auto-resolve) não tem resposta boa para aprender — apenas o silêncio.
  # Sem triagem registrada, mantém o comportamento histórico: basta ter havido
  # resposta de um agente humano em algum momento.
  def human_answered_after_handoff?
    return true if triage_note.blank?

    conversation.messages
                .where(message_type: :outgoing, private: false, sender_type: 'User')
                .exists?(created_at: triage_note.created_at..)
  end

  # `messages.content_attributes` é coluna `json` com `store` do Rails: o valor
  # é gravado duplamente codificado (string JSON dentro do JSON), então o
  # operador `->>` do Postgres nunca encontra a chave. O filtro tem que ser em
  # Ruby — as notas privadas de uma conversa são poucas.
  def triage_note
    return @triage_note if defined?(@triage_note)

    @triage_note = conversation.messages
                               .where(private: true)
                               .order(created_at: :asc)
                               .find { |message| message.content_attributes.to_h['triage_reason'].present? }
  end

  def triage_reason
    triage_note&.content_attributes&.dig('triage_reason')
  end

  def auto_judge_enabled?
    assistant.config['feature_faq_auto_judge'].present?
  end

  def find_and_separate_duplicates(faqs)
    duplicate_faqs = []
    unique_faqs = []

    faqs.each do |faq|
      combined_text = "#{faq['question']}: #{faq['answer']}"
      embedding = Captain::Llm::EmbeddingService.new(account_id: @conversation.account_id).get_embedding(combined_text)
      similar_faqs = find_similar_faqs(embedding)

      if similar_faqs.any?
        duplicate_faqs << { faq: faq, similar_faqs: similar_faqs }
      else
        unique_faqs << { faq: faq, neighbours: find_retrievable_neighbours(embedding) }
      end
    end

    [duplicate_faqs, unique_faqs]
  end

  def find_similar_faqs(embedding)
    similar_faqs = assistant
                   .responses
                   .nearest_neighbors(:embedding, embedding, distance: 'cosine')
    Rails.logger.debug(similar_faqs.map { |faq| [faq.question, faq.neighbor_distance] })
    similar_faqs.select { |record| record.neighbor_distance < DISTANCE_THRESHOLD }
  end

  # Conhecimento vivo mais próximo da candidata — é contra ele que o juiz
  # checa contradição. Diferente do dedup, aqui não há corte de distância:
  # queremos o vizinho "parecido mas diferente", que é justamente onde mora
  # a contradição.
  def find_retrievable_neighbours(embedding)
    assistant.responses
             .retrievable
             .nearest_neighbors(:embedding, embedding, distance: 'cosine')
             .limit(MAX_JUDGE_NEIGHBOURS)
             .to_a
  rescue StandardError => e
    Rails.logger.warn("[Captain::ConversationFaq] neighbour lookup failed: #{e.message}")
    []
  end

  def save_new_faqs(entries)
    entries.map { |entry| persist_faq(entry[:faq], entry[:neighbours]) }
  end

  def persist_faq(faq, neighbours)
    return create_response(faq['question'], faq['answer'], status: 'pending') unless auto_judge_enabled?

    verdict = judge(faq, neighbours)

    if verdict[:approved]
      create_response(verdict[:question], verdict[:answer], status: 'trial', verdict: verdict[:raw])
    else
      create_response(faq['question'], faq['answer'], status: 'pending', verdict: verdict[:raw])
    end
  end

  def judge(faq, neighbours)
    Captain::Llm::FaqJudgeService.new(
      assistant: assistant,
      question: faq['question'],
      answer: faq['answer'],
      conversation: conversation,
      neighbours: neighbours
    ).call
  end

  def create_response(question, answer, status:, verdict: {})
    assistant.responses.create!(
      question: question,
      answer: answer,
      status: status,
      documentable: conversation,
      source: 'human_validated',
      triage_reason: triage_reason,
      judge_verdict: verdict.presence || {},
      trial_until: status == 'trial' ? Captain::AssistantResponse::TRIAL_PERIOD.from_now : nil
    )
  end

  def log_duplicate_faqs(duplicate_faqs)
    return if duplicate_faqs.empty?

    Rails.logger.info "Found #{duplicate_faqs.length} duplicate FAQs:"
    duplicate_faqs.each do |duplicate|
      Rails.logger.info(
        "Q: #{duplicate[:faq]['question']}\n" \
        "A: #{duplicate[:faq]['answer']}\n\n" \
        "Similar existing FAQs: #{duplicate[:similar_faqs].map { |f| "Q: #{f.question} A: #{f.answer}" }.join(', ')}"
      )
    end
  end

  def generate
    response = instrument_llm_call(instrumentation_params) do
      chat
        .with_params(response_format: { type: 'json_object' })
        .with_instructions(system_prompt)
        .ask(@content)
    end
    parse_response(response.content)
  rescue RubyLLM::Error => e
    Rails.logger.error "LLM API Error: #{e.message}"
    []
  end

  def instrumentation_params
    {
      span_name: 'llm.captain.conversation_faq',
      model: @model,
      temperature: @temperature,
      account_id: @conversation.account_id,
      conversation_id: @conversation.display_id,
      feature_name: 'conversation_faq',
      messages: [
        { role: 'system', content: system_prompt },
        { role: 'user', content: @content }
      ],
      metadata: { assistant_id: @assistant.id }
    }
  end

  def system_prompt
    account_language = @conversation.account.locale_english_name
    Captain::Llm::SystemPromptsService.conversation_faq_generator(account_language)
  end

  def parse_response(response)
    return [] if response.nil?

    JSON.parse(sanitize_json_response(response)).fetch('faqs', [])
  rescue JSON::ParserError => e
    Rails.logger.error "Error in parsing GPT processed response: #{e.message}"
    []
  end
end
