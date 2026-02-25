# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Captain::Assistant::AgentRunnerService do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:scenario) { create(:captain_scenario, assistant: assistant, enabled: true) }

  let(:mock_runner) { instance_double(Agents::Runner) }
  let(:mock_agent) { instance_double(Agents::Agent) }
  let(:mock_scenario_agent) { instance_double(Agents::Agent) }
  let(:mock_result) { instance_double(Agents::RunResult, output: { 'response' => 'Test response' }, context: nil) }

  let(:message_history) do
    [
      { role: 'user', content: 'Hello there' },
      { role: 'assistant', content: 'Hi! How can I help you?', agent_name: 'Assistant' },
      { role: 'user', content: 'I need help with my account' }
    ]
  end

  before do
    allow(assistant).to receive(:agent).and_return(mock_agent)
    scenarios_relation = instance_double(Captain::Scenario)
    allow(scenarios_relation).to receive(:enabled).and_return([scenario])
    allow(assistant).to receive(:scenarios).and_return(scenarios_relation)
    allow(scenario).to receive(:agent).and_return(mock_scenario_agent)
    allow(Agents::Runner).to receive(:with_agents).and_return(mock_runner)
    allow(mock_runner).to receive(:run).and_return(mock_result)
    allow(mock_agent).to receive(:register_handoffs)
    allow(mock_scenario_agent).to receive(:register_handoffs)
  end

  describe '#initialize' do
    it 'sets instance variables correctly' do
      service = described_class.new(assistant: assistant, conversation: conversation)

      expect(service.instance_variable_get(:@assistant)).to eq(assistant)
      expect(service.instance_variable_get(:@conversation)).to eq(conversation)
      expect(service.instance_variable_get(:@callbacks)).to eq({})
    end

    it 'accepts callbacks parameter' do
      callbacks = { on_agent_thinking: proc { |x| x } }
      service = described_class.new(assistant: assistant, callbacks: callbacks)

      expect(service.instance_variable_get(:@callbacks)).to eq(callbacks)
    end
  end

  describe '#generate_response' do
    subject(:service) { described_class.new(assistant: assistant, conversation: conversation) }

    it 'builds agents and wires them together' do
      expect(assistant).to receive(:agent).and_return(mock_agent)
      scenarios_relation = instance_double(Captain::Scenario)
      allow(scenarios_relation).to receive(:enabled).and_return([scenario])
      expect(assistant).to receive(:scenarios).and_return(scenarios_relation)
      expect(scenario).to receive(:agent).and_return(mock_scenario_agent)
      expect(mock_agent).to receive(:register_handoffs).with(mock_scenario_agent)
      expect(mock_scenario_agent).to receive(:register_handoffs).with(mock_agent)

      service.generate_response(message_history: message_history)
    end

    it 'creates runner with agents' do
      expect(Agents::Runner).to receive(:with_agents).with(mock_agent, mock_scenario_agent)

      service.generate_response(message_history: message_history)
    end

    it 'runs agent with extracted user message and context' do
      expected_context = {
        session_id: "#{account.id}_#{conversation.display_id}",
        current_agent: assistant.name.to_s.parameterize(separator: '_'),
        conversation_history: [
          { role: :user, content: 'Hello there', agent_name: nil },
          { role: :assistant, content: 'Hi! How can I help you?', agent_name: nil },
          { role: :user, content: 'I need help with my account', agent_name: nil }
        ],
        state: hash_including(
          account_id: account.id,
          assistant_id: assistant.id,
          conversation: hash_including(id: conversation.id),
          contact: hash_including(id: contact.id)
        )
      }

      expect(mock_runner).to receive(:run).with(
        'I need help with my account',
        context: expected_context,
        max_turns: 100
      )

      service.generate_response(message_history: message_history)
    end

    it 'processes and formats agent result' do
      result = service.generate_response(message_history: message_history)

      expect(result).to eq({ 'response' => 'Test response', 'agent_name' => nil })
    end

    context 'when no scenarios are enabled' do
      before do
        scenarios_relation = instance_double(Captain::Scenario)
        allow(scenarios_relation).to receive(:enabled).and_return([])
        allow(assistant).to receive(:scenarios).and_return(scenarios_relation)
      end

      it 'only uses assistant agent' do
        expect(Agents::Runner).to receive(:with_agents).with(mock_agent)
        expect(mock_agent).not_to receive(:register_handoffs)

        service.generate_response(message_history: message_history)
      end
    end

    context 'when faq guardrail should force a FAQ lookup before uncertainty response' do
      let(:message_history) do
        [
          { role: 'user', content: 'Preciso da senha da internet' }
        ]
      end
      let(:mock_result) do
        instance_double(
          Agents::RunResult,
          output: {
            'response' => 'Não tenho acesso a essa informação no momento.',
            'reasoning' => 'Out of scope'
          },
          context: nil,
          messages: [
            { role: :user, content: 'Preciso da senha da internet' },
            { role: :assistant, content: 'Não tenho acesso a essa informação no momento.' }
          ]
        )
      end

      before do
        allow(assistant).to receive(:feature_faq).and_return(true)
      end

      it 'replaces uncertain response with faq answer when faq tool was not called' do
        approved_scope = double('approved_scope')
        faq_response = double('faq_response', answer: 'A senha do Wi-Fi é 1001prime.')
        allow(assistant).to receive(:responses).and_return(double(approved: approved_scope))
        allow(approved_scope).to receive(:search).with('Preciso da senha da internet').and_return([faq_response])

        result = service.generate_response(message_history: message_history)

        expect(result['response']).to eq('A senha do Wi-Fi é 1001prime.')
        expect(result['reasoning']).to eq('FAQ guardrail applied due to uncertain response without faq_lookup call.')
      end

      it 'returns faq-not-found message when search has no match' do
        approved_scope = double('approved_scope')
        allow(assistant).to receive(:responses).and_return(double(approved: approved_scope))
        allow(approved_scope).to receive(:search).and_return([])

        result = service.generate_response(message_history: message_history)

        expect(result['response']).to eq(
          'Consultei o FAQ e não encontrei essa informação cadastrada ainda. Posso te ajudar com outro tema ou te transferir para um atendente.'
        )
        expect(result['reasoning']).to eq('FAQ guardrail applied; no FAQ entry found for query.')
      end

      it 'replaces price response with faq answer when faq tool was not called in current turn' do
        allow(mock_result).to receive(:output).and_return(
          {
            'response' => 'Rodrigo, para confirmar a reserva da suíte Aluba, o valor total é R$ 260,00 e o sinal é R$ 130,00.',
            'reasoning' => 'Valor calculado para reserva'
          }
        )
        allow(mock_result).to receive(:messages).and_return(
          [
            { role: :user, content: 'Rodrigo borba machado CPF: 00251938131 para amanhã na pernoite mesmo duração de 2 horas' },
            {
              role: :assistant,
              content: 'Rodrigo, para confirmar a reserva da suíte Aluba, o valor total é R$ 260,00 e o sinal é R$ 130,00.'
            }
          ]
        )

        approved_scope = double('approved_scope')
        faq_response = double('faq_response', answer: 'O valor da suíte Aluba é R$ 5,00 para qualquer duração.')
        allow(assistant).to receive(:responses).and_return(double(approved: approved_scope))
        allow(approved_scope).to receive(:search) do |query|
          if query.include?('valor da suíte Aluba')
            [faq_response]
          else
            []
          end
        end

        result = service.generate_response(message_history: message_history)

        expect(result['response']).to eq('O valor da suíte Aluba é R$ 5,00 para qualquer duração.')
        expect(result['reasoning']).to eq('FAQ guardrail applied due to price response without faq_lookup call.')
      end

      it 'does not force fallback when faq_lookup was already called' do
        allow(mock_result).to receive(:messages).and_return(
          [
            { role: :user, content: 'Preciso da senha da internet' },
            {
              role: :assistant,
              content: '',
              tool_calls: [{ id: 'call_1', name: 'captain--tools--faq_lookup', arguments: { query: 'senha da internet' } }]
            }
          ]
        )
        approved_scope = double('approved_scope')
        allow(assistant).to receive(:responses).and_return(double(approved: approved_scope))
        expect(approved_scope).not_to receive(:search)

        result = service.generate_response(message_history: message_history)

        expect(result['response']).to eq('Não tenho acesso a essa informação no momento.')
      end

      it 'forces fallback when faq_lookup happened only in a previous turn' do
        allow(mock_result).to receive(:messages).and_return(
          [
            { role: :user, content: 'Qual o horário do café?' },
            {
              role: :assistant,
              content: '',
              tool_calls: [{ id: 'call_prev', name: 'captain--tools--faq_lookup', arguments: { query: 'horário do café' } }]
            },
            { role: :assistant, content: 'O café é servido das 07h às 09h.' },
            { role: :user, content: 'Preciso da senha da internet' },
            { role: :assistant, content: 'Não tenho acesso a essa informação no momento.' }
          ]
        )
        approved_scope = double('approved_scope')
        faq_response = double('faq_response', answer: 'A senha do Wi-Fi é 1001prime.')
        allow(assistant).to receive(:responses).and_return(double(approved: approved_scope))
        allow(approved_scope).to receive(:search).with('Preciso da senha da internet').and_return([faq_response])

        result = service.generate_response(message_history: message_history)

        expect(result['response']).to eq('A senha do Wi-Fi é 1001prime.')
        expect(result['reasoning']).to eq('FAQ guardrail applied due to uncertain response without faq_lookup call.')
      end
    end

    context 'when agent result is a string' do
      let(:mock_result) { instance_double(Agents::RunResult, output: 'Simple string response', context: nil) }

      it 'formats string response correctly' do
        result = service.generate_response(message_history: message_history)

        expect(result).to eq({
                               'response' => 'Simple string response',
                               'reasoning' => 'Processed by agent',
                               'agent_name' => nil
                             })
      end
    end

    context 'when agent result is a duplicated JSON string' do
      let(:mock_result) do
        instance_double(
          Agents::RunResult,
          output: <<~JSON_OUTPUT.strip,
            {"response":"Rodrigo, valor total R$ 260,00.","reasoning":"Primeira resposta","reaction_emoji":"💰"}
            {"response":"Rodrigo, para confirmar a reserva, o sinal é R$ 130,00. Posso gerar o Pix?","reasoning":"Resposta final","reaction_emoji":"💰"}
          JSON_OUTPUT
          context: nil
        )
      end

      it 'parses structured json and returns only the final response text' do
        result = service.generate_response(message_history: message_history)

        expect(result).to eq({
                               'response' => 'Rodrigo, para confirmar a reserva, o sinal é R$ 130,00. Posso gerar o Pix?',
                               'reasoning' => 'Resposta final',
                               'reaction_emoji' => '💰',
                               'agent_name' => nil
                             })
      end
    end

    context 'when an error occurs' do
      let(:error) { StandardError.new('Test error') }

      before do
        allow(mock_runner).to receive(:run).and_raise(error)
        allow(ChatwootExceptionTracker).to receive(:new).and_return(
          instance_double(ChatwootExceptionTracker, capture_exception: true)
        )
      end

      it 'captures exception and returns error response' do
        expect(ChatwootExceptionTracker).to receive(:new).with(error, account: conversation.account)

        result = service.generate_response(message_history: message_history)

        expect(result).to eq({
                               'response' => 'conversation_handoff',
                               'reasoning' => 'Error occurred: Test error'
                             })
      end

      it 'logs error details' do
        expect(Rails.logger).to receive(:error).with('[Captain V2] AgentRunnerService error: Test error')
        expect(Rails.logger).to receive(:error).with(kind_of(String))

        service.generate_response(message_history: message_history)
      end

      context 'when conversation is nil' do
        subject(:service) { described_class.new(assistant: assistant, conversation: nil) }

        it 'handles missing conversation gracefully' do
          expect(ChatwootExceptionTracker).to receive(:new).with(error, account: nil)

          result = service.generate_response(message_history: message_history)

          expect(result).to eq({
                                 'response' => 'conversation_handoff',
                                 'reasoning' => 'Error occurred: Test error'
                               })
        end
      end
    end
  end

  describe '#build_context' do
    subject(:service) { described_class.new(assistant: assistant, conversation: conversation) }

    it 'builds context with conversation history and state' do
      context = service.send(:build_context, message_history)

      expect(context).to include(
        conversation_history: array_including(
          { role: :user, content: 'Hello there', agent_name: nil },
          { role: :assistant, content: 'Hi! How can I help you?', agent_name: nil }
        ),
        state: hash_including(
          account_id: account.id,
          assistant_id: assistant.id
        )
      )
    end

    context 'with multimodal content' do
      let(:multimodal_message_history) do
        [
          {
            role: 'user',
            content: [
              { type: 'text', text: 'Can you help with this image?' },
              { type: 'image_url', image_url: { url: 'https://example.com/image.jpg' } }
            ]
          }
        ]
      end

      it 'extracts text content from multimodal messages' do
        context = service.send(:build_context, multimodal_message_history)

        expect(context[:conversation_history].first[:content]).to eq('Can you help with this image?')
      end
    end
  end

  describe '#extract_last_user_message' do
    subject(:service) { described_class.new(assistant: assistant, conversation: conversation) }

    it 'extracts the last user message' do
      result = service.send(:extract_last_user_message, message_history)

      expect(result).to eq('I need help with my account')
    end
  end

  describe '#extract_text_from_content' do
    subject(:service) { described_class.new(assistant: assistant, conversation: conversation) }

    it 'extracts text from string content' do
      result = service.send(:extract_text_from_content, 'Simple text')

      expect(result).to eq('Simple text')
    end

    it 'extracts response from hash content' do
      content = { 'response' => 'Hash response' }
      result = service.send(:extract_text_from_content, content)

      expect(result).to eq('Hash response')
    end

    it 'extracts text from multimodal array content' do
      content = [
        { type: 'text', text: 'First part' },
        { type: 'image_url', image_url: { url: 'image.jpg' } },
        { type: 'text', text: 'Second part' }
      ]

      result = service.send(:extract_text_from_content, content)

      expect(result).to eq('First part Second part')
    end
  end

  describe '#build_state' do
    subject(:service) { described_class.new(assistant: assistant, conversation: conversation) }

    it 'builds state with assistant and account information' do
      state = service.send(:build_state)

      expect(state).to include(
        account_id: account.id,
        assistant_id: assistant.id,
        assistant_config: assistant.config
      )
    end

    it 'includes conversation attributes when conversation is present' do
      state = service.send(:build_state)

      expect(state[:conversation]).to include(
        id: conversation.id,
        inbox_id: inbox.id,
        contact_id: contact.id,
        status: conversation.status
      )
    end

    it 'includes contact attributes when contact is present' do
      state = service.send(:build_state)

      expect(state[:contact]).to include(
        id: contact.id,
        name: contact.name,
        email: contact.email
      )
    end

    context 'when conversation is nil' do
      subject(:service) { described_class.new(assistant: assistant, conversation: nil) }

      it 'builds state without conversation and contact' do
        state = service.send(:build_state)

        expect(state).to include(
          account_id: account.id,
          assistant_id: assistant.id,
          assistant_config: assistant.config
        )
        expect(state).not_to have_key(:conversation)
        expect(state).not_to have_key(:contact)
      end
    end
  end

  describe '#add_usage_metadata_callback' do
    it 'sets credit_used=false when handoff tool is used' do
      service = described_class.new(assistant: assistant, conversation: conversation)
      runner = instance_double(Agents::AgentRunner)
      tool_complete_callback = nil
      run_complete_callback = nil
      span_class = Class.new do
        def set_attribute(*); end
      end
      root_span = instance_double(span_class)
      context_wrapper = Struct.new(:context).new({ __otel_tracing: { root_span: root_span } })

      allow(ChatwootApp).to receive(:otel_enabled?).and_return(true)
      allow(runner).to receive(:on_tool_complete) do |&block|
        tool_complete_callback = block
        runner
      end
      allow(runner).to receive(:on_run_complete) do |&block|
        run_complete_callback = block
        runner
      end

      service.send(:add_usage_metadata_callback, runner)

      tool_complete_callback.call(Captain::Tools::HandoffTool.new(assistant).name, 'ok', context_wrapper)

      expect(root_span).to receive(:set_attribute).with('langfuse.trace.metadata.credit_used', 'false')
      run_complete_callback.call('assistant', nil, context_wrapper)
    end

    it 'sets credit_used=true when handoff tool is not used' do
      service = described_class.new(assistant: assistant, conversation: conversation)
      runner = instance_double(Agents::AgentRunner)
      run_complete_callback = nil
      span_class = Class.new do
        def set_attribute(*); end
      end
      root_span = instance_double(span_class)
      context_wrapper = Struct.new(:context).new({ __otel_tracing: { root_span: root_span } })

      allow(ChatwootApp).to receive(:otel_enabled?).and_return(true)
      allow(runner).to receive(:on_tool_complete).and_return(runner)
      allow(runner).to receive(:on_run_complete) do |&block|
        run_complete_callback = block
        runner
      end

      service.send(:add_usage_metadata_callback, runner)

      expect(root_span).to receive(:set_attribute).with('langfuse.trace.metadata.credit_used', 'true')
      run_complete_callback.call('assistant', nil, context_wrapper)
    end
  end

  describe 'constants' do
    it 'defines conversation state attributes' do
      expect(described_class::CONVERSATION_STATE_ATTRIBUTES).to include(
        :id, :display_id, :inbox_id, :contact_id, :status, :priority
      )
    end

    it 'defines contact state attributes' do
      expect(described_class::CONTACT_STATE_ATTRIBUTES).to include(
        :id, :name, :email, :phone_number, :identifier, :contact_type
      )
    end
  end
end
