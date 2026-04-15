module Concerns::Agentable
  extend ActiveSupport::Concern

  def agent
    Agents::Agent.new(
      name: agent_name,
      instructions: ->(context) { agent_instructions(context) },
      tools: agent_tools,
      model: agent_model,
      temperature: temperature.to_f || 0.7,
      response_schema: agent_response_schema
    )
  end

  def agent_instructions(context = nil)
    enhanced_context = prompt_context

    if context
      state = context.context[:state] || {}
      conversation_data = state[:conversation] || {}
      contact_data = state[:contact] || {}
      enhanced_context = enhanced_context.merge(
        conversation: conversation_data,
        contact: contact_data,
        concierge: resolve_concierge_context(conversation_data),
        reservation: resolve_reservation_context(conversation_data)
      )
    end

    ctx = enhanced_context.with_indifferent_access

    custom = orchestrator_prompt_override
    if custom.present?
      Captain::PromptRenderer.render_string(custom, ctx)
    else
      Captain::PromptRenderer.render(template_name, ctx)
    end
  end

  def default_orchestrator_prompt
    Captain::PromptRenderer.read_template(template_name)
  end

  private

  def agent_name
    raise NotImplementedError, "#{self.class} must implement agent_name"
  end

  def orchestrator_prompt_override
    respond_to?(:orchestrator_prompt) ? orchestrator_prompt.presence : nil
  end

  def template_name
    self.class.name.demodulize.underscore
  end

  def agent_tools
    []  # Default implementation, override if needed
  end

  def agent_model
    InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_MODEL')&.value.presence || LlmConstants::DEFAULT_MODEL
  end

  def agent_response_schema
    Captain::ResponseSchema
  end

  def prompt_context
    raise NotImplementedError, "#{self.class} must implement prompt_context"
  end

  def resolve_concierge_context(conversation_data)
    unit = resolve_current_unit(conversation_data)
    return default_concierge_context if unit.blank?

    {
      'persona_name' => unit.concierge_persona_name,
      'unit_name' => unit.name.to_s,
      'knowledge' => unit.concierge_knowledge,
      'variables' => unit.concierge_variables
    }
  end

  def resolve_reservation_context(conversation_data)
    conv = lookup_conversation(conversation_data)
    return {} if conv.blank?

    reservation = Captain::Reservation
                  .where(account_id: conv.account_id, contact_id: conv.contact_id)
                  .order(created_at: :desc)
                  .first
    return {} if reservation.blank?

    Captain::Lifecycle::ContextBuilder.build(reservation).fetch('reservation', {})
  end

  def resolve_current_unit(conversation_data)
    conv = lookup_conversation(conversation_data)
    return nil if conv.blank?

    unit_id = conv.custom_attributes.to_h['current_unit_id']
    return nil if unit_id.blank?

    Captain::Unit.find_by(id: unit_id)
  end

  def lookup_conversation(conversation_data)
    return nil if conversation_data.blank?

    id = conversation_data.is_a?(Hash) ? (conversation_data[:id] || conversation_data['id']) : nil
    return nil if id.blank?

    ::Conversation.find_by(id: id)
  end

  def default_concierge_context
    { 'persona_name' => 'Sofia', 'unit_name' => '', 'knowledge' => '', 'variables' => {} }
  end
end
