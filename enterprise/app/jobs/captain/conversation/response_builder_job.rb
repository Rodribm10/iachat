require_dependency 'captain/conversation/reaction_policy'

class Captain::Conversation::ResponseBuilderJob < ApplicationJob
  include Captain::Conversation::ReactionPolicy

  MAX_MESSAGE_LENGTH = 10_000
  REACTION_SAMPLE_RATE = Captain::Conversation::ReactionPolicy::REACTION_SAMPLE_RATE

  retry_on ActiveStorage::FileNotFoundError, attempts: 3, wait: 2.seconds
  retry_on Faraday::BadRequestError, attempts: 3, wait: 2.seconds

  def perform(conversation, assistant, message = nil)
    @conversation = conversation
    @inbox = conversation.inbox
    @assistant = assistant

    # Cancel if there are newer messages after the provided message
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

  def humanized_delay(response_text)
    return if response_text.blank?

    # Simulação: ~45ms por caracter (digitadores rápidos / humanos focados)
    typing_speed = 45
    target_delay = (response_text.length * typing_speed) / 1000.0

    # Limite Mínimo (2s) para não parecer robótico demais em palavras como "Sim".
    # Limite Máximo (7s) para não prender a UI do chat por longo tempo dando ansiedade ao usuário
    target_delay = target_delay.clamp(2.0, 7.0)

    elapsed_time = Time.zone.now - @start_time
    remaining_delay = target_delay - elapsed_time

    sleep(remaining_delay) if remaining_delay.positive?
  end

  def collect_previous_messages
    @conversation
      .messages
      .where(message_type: [:incoming, :outgoing])
      .where(private: false)
      .map do |message|
      message_hash = {
        content: prepare_multimodal_message_content(message),
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
