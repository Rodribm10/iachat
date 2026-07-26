require 'rails_helper'

RSpec.describe Captain::Llm::ConversationFaqService do
  let(:captain_assistant) { create(:captain_assistant) }
  let(:conversation) { create(:conversation, first_reply_created_at: Time.zone.now) }
  let(:service) { described_class.new(captain_assistant, conversation) }
  let(:embedding_service) { instance_double(Captain::Llm::EmbeddingService) }
  let(:mock_chat) { instance_double(RubyLLM::Chat) }
  let(:sample_faqs) do
    [
      { 'question' => 'What is the purpose?', 'answer' => 'To help users.' },
      { 'question' => 'How does it work?', 'answer' => 'Through AI.' }
    ]
  end
  let(:mock_response) do
    instance_double(RubyLLM::Message, content: { faqs: sample_faqs }.to_json)
  end

  before do
    create(:installation_config, name: 'CAPTAIN_OPEN_AI_API_KEY', value: 'test-key')
    allow(Captain::Llm::EmbeddingService).to receive(:new).and_return(embedding_service)
    allow(RubyLLM).to receive(:chat).and_return(mock_chat)
    allow(mock_chat).to receive(:with_temperature).and_return(mock_chat)
    allow(mock_chat).to receive(:with_params).and_return(mock_chat)
    allow(mock_chat).to receive(:with_instructions).and_return(mock_chat)
    allow(mock_chat).to receive(:ask).and_return(mock_response)
  end

  describe '#generate_and_deduplicate' do
    context 'when successful' do
      before do
        allow(embedding_service).to receive(:get_embedding).and_return([0.1, 0.2, 0.3])
        allow(captain_assistant.responses).to receive(:nearest_neighbors).and_return([])
      end

      it 'creates new FAQs for valid conversation content' do
        expect do
          service.generate_and_deduplicate
        end.to change(captain_assistant.responses, :count).by(2)
      end

      it 'saves FAQs with pending status linked to conversation' do
        service.generate_and_deduplicate
        expect(
          captain_assistant.responses.pluck(:question, :answer, :status, :documentable_id)
        ).to contain_exactly(
          ['What is the purpose?', 'To help users.', 'pending', conversation.id],
          ['How does it work?', 'Through AI.', 'pending', conversation.id]
        )
      end
    end

    context 'without human interaction' do
      let(:conversation) { create(:conversation) }

      it 'returns an empty array without generating FAQs' do
        expect(service.generate_and_deduplicate).to eq([])
      end

      it 'does not call the LLM API' do
        expect(RubyLLM).not_to receive(:chat)
        service.generate_and_deduplicate
      end
    end

    context 'when finding duplicates' do
      let(:existing_response) do
        create(:captain_assistant_response, assistant: captain_assistant, question: 'Similar question', answer: 'Similar answer')
      end
      let(:similar_neighbor) do
        OpenStruct.new(
          id: 1,
          question: existing_response.question,
          answer: existing_response.answer,
          neighbor_distance: 0.1
        )
      end

      before do
        allow(embedding_service).to receive(:get_embedding).and_return([0.1, 0.2, 0.3])
        allow(captain_assistant.responses).to receive(:nearest_neighbors).and_return([similar_neighbor])
      end

      it 'filters out duplicate FAQs based on embedding similarity' do
        expect do
          service.generate_and_deduplicate
        end.not_to change(captain_assistant.responses, :count)
      end
    end

    context 'when LLM API fails' do
      before do
        allow(mock_chat).to receive(:ask).and_raise(RubyLLM::Error.new(nil, 'API Error'))
        allow(Rails.logger).to receive(:error)
      end

      it 'returns empty array and logs the error' do
        expect(Rails.logger).to receive(:error).with('LLM API Error: API Error')
        expect(service.generate_and_deduplicate).to eq([])
      end
    end

    context 'when JSON parsing fails' do
      let(:invalid_response) do
        instance_double(RubyLLM::Message, content: 'invalid json')
      end

      before do
        allow(mock_chat).to receive(:ask).and_return(invalid_response)
      end

      it 'handles JSON parsing errors gracefully' do
        expect(Rails.logger).to receive(:error).with(/Error in parsing GPT processed response:/)
        expect(service.generate_and_deduplicate).to eq([])
      end
    end

    context 'when response content is nil' do
      let(:nil_response) do
        instance_double(RubyLLM::Message, content: nil)
      end

      before do
        allow(mock_chat).to receive(:ask).and_return(nil_response)
      end

      it 'returns empty array' do
        expect(service.generate_and_deduplicate).to eq([])
      end
    end
  end

  describe 'human triage guard' do
    let(:agent) { create(:user, account: conversation.account) }

    before do
      allow(embedding_service).to receive(:get_embedding).and_return([0.1, 0.2, 0.3])
      allow(captain_assistant.responses).to receive(:nearest_neighbors).and_return([])
    end

    def create_triage_note(at:)
      conversation.messages.create!(
        message_type: :outgoing, private: true, created_at: at,
        account_id: conversation.account_id, inbox_id: conversation.inbox_id,
        content: 'Triagem humana ativa', content_attributes: { triage_reason: 'sem_resposta_segura' }
      )
    end

    def create_agent_reply(at:)
      conversation.messages.create!(
        message_type: :outgoing, private: false, created_at: at, sender: agent,
        account_id: conversation.account_id, inbox_id: conversation.inbox_id,
        content: 'Aceitamos sim, pode trazer.'
      )
    end

    context 'when the conversation went to triage and nobody answered' do
      before { create_triage_note(at: 1.hour.ago) }

      it 'learns nothing — silence is not validated knowledge' do
        expect { service.generate_and_deduplicate }.not_to change(captain_assistant.responses, :count)
      end

      it 'ignores an agent reply that happened before the triage' do
        create_agent_reply(at: 3.hours.ago)

        expect { service.generate_and_deduplicate }.not_to change(captain_assistant.responses, :count)
      end
    end

    context 'when a human answered after the triage' do
      before do
        create_triage_note(at: 2.hours.ago)
        create_agent_reply(at: 1.hour.ago)
      end

      it 'learns from the conversation' do
        expect { service.generate_and_deduplicate }.to change(captain_assistant.responses, :count).by(2)
      end

      it 'records the triage reason on the learned FAQ' do
        service.generate_and_deduplicate

        expect(captain_assistant.responses.pluck(:triage_reason).uniq).to eq(['sem_resposta_segura'])
      end

      it 'tags the source as human validated' do
        service.generate_and_deduplicate

        expect(captain_assistant.responses.pluck(:source).uniq).to eq(['human_validated'])
      end
    end
  end

  describe 'automatic judging' do
    let(:judge) { instance_double(Captain::Llm::FaqJudgeService) }

    before do
      allow(embedding_service).to receive(:get_embedding).and_return([0.1, 0.2, 0.3])
      allow(captain_assistant.responses).to receive(:nearest_neighbors).and_return([])
      captain_assistant.update!(config: captain_assistant.config.merge('feature_faq_auto_judge' => true))
      allow(Captain::Llm::FaqJudgeService).to receive(:new).and_return(judge)
    end

    context 'when the judge approves' do
      before do
        allow(judge).to receive(:call).and_return(
          { approved: true, question: 'P revisada', answer: 'R revisada', raw: { 'fidelidade' => { 'aprovado' => true } } }
        )
      end

      it 'puts the FAQ in quarantine instead of the approval queue' do
        service.generate_and_deduplicate

        expect(captain_assistant.responses.pluck(:status).uniq).to eq(['trial'])
      end

      it 'sets the quarantine deadline' do
        service.generate_and_deduplicate

        expect(captain_assistant.responses.first.trial_until).to be_within(1.minute).of(30.days.from_now)
      end

      it 'saves the revised wording and the verdict' do
        service.generate_and_deduplicate
        response = captain_assistant.responses.first

        expect(response.question).to eq('P revisada')
        expect(response.answer).to eq('R revisada')
        expect(response.judge_verdict).to be_present
      end
    end

    context 'when the judge rejects' do
      before do
        allow(judge).to receive(:call).and_return(
          { approved: false, question: 'P', answer: 'R', raw: { 'generalizavel' => { 'aprovado' => false } } }
        )
      end

      it 'leaves the FAQ pending for a human decision' do
        service.generate_and_deduplicate

        expect(captain_assistant.responses.pluck(:status).uniq).to eq(['pending'])
      end

      it 'keeps the rejection reasoning for the exception queue' do
        service.generate_and_deduplicate

        expect(captain_assistant.responses.first.judge_verdict).to be_present
      end

      it 'does not expose the FAQ to the assistant' do
        service.generate_and_deduplicate

        expect(captain_assistant.responses.retrievable).to be_empty
      end
    end

    context 'when the feature flag is off' do
      before do
        captain_assistant.update!(config: captain_assistant.config.merge('feature_faq_auto_judge' => false))
      end

      it 'preserves the legacy behaviour and never calls the judge' do
        expect(Captain::Llm::FaqJudgeService).not_to receive(:new)

        service.generate_and_deduplicate

        expect(captain_assistant.responses.pluck(:status).uniq).to eq(['pending'])
      end
    end
  end

  describe 'language handling' do
    context 'when conversation has different language' do
      let(:account) { create(:account, locale: 'fr') }
      let(:conversation) do
        create(:conversation, account: account, first_reply_created_at: Time.zone.now)
      end

      before do
        allow(embedding_service).to receive(:get_embedding).and_return([0.1, 0.2, 0.3])
        allow(captain_assistant.responses).to receive(:nearest_neighbors).and_return([])
      end

      it 'uses account language for system prompt' do
        expect(Captain::Llm::SystemPromptsService).to receive(:conversation_faq_generator)
          .with('french')
          .at_least(:once)
          .and_call_original

        service.generate_and_deduplicate
      end
    end
  end
end
