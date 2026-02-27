require_dependency 'captain/conversation/reaction_policy'
require_dependency 'captain/errors/system_prompt_leak_error'

# rubocop:disable Metrics/ClassLength
class Captain::Conversation::ResponseBuilderJob < ApplicationJob
  include Captain::Conversation::ReactionPolicy

  MAX_MESSAGE_LENGTH = 10_000
  REACTION_SAMPLE_RATE = Captain::Conversation::ReactionPolicy::REACTION_SAMPLE_RATE

  # Padrões que indicam que o LLM retornou o system prompt em vez de uma resposta ao cliente.
  # Qualquer mensagem que comece com esses padrões deve ser bloqueada e redirecionar para handoff humano.
  SYSTEM_PROMPT_LEAK_PATTERNS = [
    /\A\[Contexto\]/i,
    /\A<contexto>/i,
    /\A#\s*System Context/i,
    /\A\[Identity\]/i,
    /\A\[Context\]/i,
    /\AYou are part of Captain,/i
  ].freeze

  retry_on ActiveStorage::FileNotFoundError, attempts: 3, wait: 2.seconds
  retry_on Faraday::BadRequestError, attempts: 3, wait: 2.seconds

  def perform(conversation, assistant, message = nil)
    @conversation = conversation
    @inbox = conversation.inbox
    @assistant = assistant

    # Cancel if there are newer messages after the provided message
    return if debounce_requested?(message)

    # Simulate reading the message before starting to type
    delay_before_typing(message)

    # Re-check debounce to avoid race condition where another message arrived during reading sleep
    return if debounce_requested?(message)

    # Trigger typing on before processing
    simulate_typing('typing_on')
    @start_time = Time.zone.now

    begin
      execute_agent_response
    ensure
      simulate_typing('typing_off')
    end
  end

  private

  def execute_agent_response
    Current.executed_by = @assistant

    if captain_v2_enabled?
      generate_response_with_v2
    else
      generate_and_process_response
    end
  rescue Captain::Errors::SystemPromptLeakError => e
    Rails.logger.error("[CAPTAIN][ResponseBuilderJob] #{e.message} — transferindo para humano")
    process_action('handoff')
  rescue StandardError => e
    raise e if e.is_a?(ActiveStorage::FileNotFoundError) || e.is_a?(Faraday::BadRequestError)

    handle_error(e)
  ensure
    Current.executed_by = nil
  end

  def debounce_requested?(message)
    return false if message.blank?

    last_incoming = @conversation.messages.where(message_type: :incoming).last
    last_incoming.present? && last_incoming.id != message.id
  end

  def delay_before_typing(message)
    return if message.blank? || message.content.blank?

    chars_count = message.content.to_s.length
    configured_delay = @inbox.typing_delay.to_i

    # Simulate reading time proportional to configured delay. Max reading is ~40% of configured delay.
    max_reading = configured_delay.positive? ? (configured_delay * 0.4) : 4.0
    min_reading = [1.0, max_reading].min
    reading_time = (chars_count / 25.0).clamp(min_reading, max_reading)

    # Add jitter (randomness between 85% and 120%)
    jitter = 0.85 + (rand * 0.35)
    delay = reading_time * jitter

    Rails.logger.info(
      "[CAPTAIN][ResponseBuilderJob] Simulating reading delay of #{delay.round(2)}s " \
      "for message of #{chars_count} chars"
    )
    sleep(delay)
  end

  def simulate_typing(status)
    # Trigger ActionCable for the Chatwoot dashboard
    cable_status = status == 'typing_on' ? 'on' : 'off'
    Conversations::TypingStatusManager.new(
      @conversation,
      @assistant,
      { typing_status: cable_status, is_private: false }
    ).toggle_typing_status

    # Trigger external typing indicator (WhatsApp, API channels, etc)
    @inbox.channel.toggle_typing_status(status, conversation: @conversation) if @inbox.channel.respond_to?(:toggle_typing_status)
  rescue StandardError => e
    Rails.logger.error("[CAPTAIN] Failed to simulate typing #{status}: #{e.message}")
  end

  delegate :account, :inbox, to: :@conversation

  def generate_and_process_response
    @response = Captain::Llm::AssistantChatService.new(assistant: @assistant, conversation_id: @conversation.display_id).generate_response(
      message_history: collect_previous_messages
    )
    process_response
  end

  def generate_response_with_v2
    @response = Captain::Assistant::AgentRunnerService.new(assistant: @assistant, conversation: @conversation).generate_response(
      message_history: collect_previous_messages
    )
    process_response
  end

  def process_response
    ActiveRecord::Base.transaction do
      if handoff_requested?
        process_action('handoff')
      else
        humanized_delay(@response['response'])
        create_messages
        Rails.logger.info("[CAPTAIN][ResponseBuilderJob] Incrementing response usage for #{account.id}")
        account.increment_response_usage
      end
    end
  end

  # rubocop:disable Metrics/AbcSize
  def humanized_delay(response_text)
    return if response_text.blank?

    text = response_text.to_s
    chars_count = text.length
    punctuation_pauses = text.count(',.!?;:')
    configured_delay = @inbox.typing_delay.to_i

    # Modela tempo de digitação de forma mais humana no WhatsApp:
    # - Velocidade média de digitação: ~15 a 20 caracteres por segundo
    # - Pequenas pausas por pontuação
    base_time = (chars_count / 15.0) + (punctuation_pauses * 0.25)

    # Se configurado, max_typing é o valor escolhido, senão, 12s
    max_typing = configured_delay.positive? ? configured_delay.to_f : 12.0
    min_delay = [2.0, max_typing].min

    # Adicionando uma ligeira variação humana
    jitter = 0.85 + (rand * 0.35)
    target_delay = (base_time * jitter).clamp(min_delay, max_typing)

    elapsed_time = Time.zone.now - @start_time
    remaining_delay = target_delay - elapsed_time

    return unless remaining_delay.positive?

    Rails.logger.info(
      "[CAPTAIN][ResponseBuilderJob] Simulating typing delay of #{remaining_delay.round(2)}s " \
      "(target: #{target_delay.round(2)}s, total elapsed: #{elapsed_time.round(2)}s, configured_max: #{max_typing}s)"
    )
    sleep(remaining_delay)
  end
  # rubocop:enable Metrics/AbcSize

  def collect_previous_messages
    @conversation
      .messages
      .where(message_type: [:incoming, :outgoing])
      .where(private: false)
      .filter_map do |message|
      content = prepare_multimodal_message_content(message)

      # Ignorar mensagens contaminadas por vazamento de system prompt no histórico
      if message.message_type == 'outgoing' && system_prompt_leak?(content)
        Rails.logger.warn("[CAPTAIN][ResponseBuilderJob] Skipping leaked system-prompt message id=#{message.id} from history")
        next
      end

      message_hash = {
        content: content,
        role: determine_role(message)
      }

      # Include agent_name if present in additional_attributes
      message_hash[:agent_name] = message.additional_attributes['agent_name'] if message.additional_attributes&.dig('agent_name').present?

      message_hash
    end
  end

  def determine_role(message)
    message.message_type == 'incoming' ? 'user' : 'assistant'
  end

  def prepare_multimodal_message_content(message)
    Captain::OpenAiMessageBuilderService.new(message: message).generate_content
  end

  def handoff_requested?
    @response['response'] == 'conversation_handoff'
  end

  def process_action(action)
    case action
    when 'handoff'
      I18n.with_locale(@assistant.account.locale) do
        create_handoff_message
        @conversation.bot_handoff!
        send_out_of_office_message_if_applicable
      end
    end
  end

  def send_out_of_office_message_if_applicable
    # Campaign conversations should never receive OOO templates — the campaign itself
    # serves as the initial outreach, and OOO would be confusing in that context.
    return if @conversation.campaign.present?

    ::MessageTemplates::Template::OutOfOffice.perform_if_applicable(@conversation)
  end

  def create_handoff_message
    create_outgoing_message(
      @assistant.config['handoff_message'].presence || I18n.t('conversations.captain.handoff')
    )
  end

  def create_messages
    target_message = last_incoming_message
    create_reaction(target_message) if should_send_reaction_for?(target_message)

    validate_message_content!(@response['response'])
    create_outgoing_message(@response['response'], agent_name: @response['agent_name'])
  end

  def create_reaction(target_message)
    @conversation.messages.create!(
      message_type: :outgoing,
      account_id: account.id,
      inbox_id: inbox.id,
      sender: @assistant,
      content: @response['reaction_emoji'],
      content_attributes: {
        'is_reaction' => true,
        'in_reply_to' => target_message.id,
        'in_reply_to_external_id' => target_message.source_id
      }
    )
  end

  def validate_message_content!(content)
    raise ArgumentError, 'Message content cannot be blank' if content.blank?

    return unless system_prompt_leak?(content)

    Rails.logger.error(
      '[CAPTAIN][ResponseBuilderJob] SYSTEM PROMPT LEAK DETECTADO — ' \
      "bloqueando mensagem pública. Prévia: #{content.to_s.truncate(300)}"
    )
    raise Captain::Errors::SystemPromptLeakError,
          'Resposta do LLM contém conteúdo do system prompt — transferindo para humano'
  end

  def system_prompt_leak?(content)
    text = content.is_a?(String) ? content.strip : content.to_s.strip
    SYSTEM_PROMPT_LEAK_PATTERNS.any? { |pattern| text.match?(pattern) }
  end

  def create_outgoing_message(message_content, agent_name: nil)
    additional_attrs = {}
    additional_attrs[:agent_name] = agent_name if agent_name.present?

    @conversation.messages.create!(
      message_type: :outgoing,
      account_id: account.id,
      inbox_id: inbox.id,
      sender: @assistant,
      content: message_content,
      additional_attributes: additional_attrs
    )
  end

  def handle_error(error)
    log_error(error)
    process_action('handoff')
    true
  end

  def log_error(error)
    ChatwootExceptionTracker.new(error, account: account).capture_exception
  end

  def captain_v2_enabled?
    account.feature_enabled?('captain_integration_v2')
  end
end
# rubocop:enable Metrics/ClassLength
