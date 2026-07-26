require 'rails_helper'

RSpec.describe Captain::Llm::FaqJudgeService do
  let(:assistant) { create(:captain_assistant) }
  let(:conversation) { create(:conversation) }
  let(:mock_chat) { instance_double(RubyLLM::Chat) }

  let(:approved_payload) do
    {
      'fidelidade' => { 'aprovado' => true, 'motivo' => 'bate com a resposta do humano' },
      'generalizavel' => { 'aprovado' => true, 'motivo' => 'sem dado pessoal' },
      'nao_contradiz' => { 'aprovado' => true, 'motivo' => 'nada conflitante' },
      'politica' => { 'aprovado' => true, 'motivo' => 'tom adequado' },
      'humanizada' => { 'nota' => 4, 'motivo' => 'natural' },
      'autocontida' => { 'nota' => 5, 'motivo' => 'completa' },
      'pergunta_revisada' => 'Vocês aceitam pet?',
      'resposta_revisada' => 'Não aceitamos animais em nenhuma unidade.'
    }
  end

  def stub_llm(payload)
    allow(RubyLLM).to receive(:chat).and_return(mock_chat)
    allow(mock_chat).to receive(:with_temperature).and_return(mock_chat)
    allow(mock_chat).to receive(:with_params).and_return(mock_chat)
    allow(mock_chat).to receive(:ask).and_return(instance_double(RubyLLM::Message, content: payload.to_json))
  end

  def judge(question: 'Vocês aceitam pet?', answer: 'Não aceitamos animais em nenhuma unidade.', neighbours: [])
    described_class.new(
      assistant: assistant, question: question, answer: answer,
      conversation: conversation, neighbours: neighbours
    ).call
  end

  describe '#call' do
    context 'when every eliminatory criterion passes' do
      before { stub_llm(approved_payload) }

      it 'approves the FAQ' do
        expect(judge[:approved]).to be(true)
      end

      it 'records the full verdict with model and timestamp' do
        verdict = judge[:raw]

        expect(verdict).to include('fidelidade', 'generalizavel', 'nao_contradiz', 'politica', 'humanizada', 'autocontida')
        expect(verdict['model']).to be_present
        expect(verdict['judged_at']).to be_present
      end
    end

    describe 'eliminatory criteria' do
      Captain::Llm::FaqJudgeService::ELIMINATORY_CRITERIA.each do |criterion|
        it "rejects the FAQ when #{criterion} fails" do
          stub_llm(approved_payload.merge(criterion => { 'aprovado' => false, 'motivo' => 'reprovado' }))

          expect(judge[:approved]).to be(false)
        end
      end

      it 'keeps the original text when rejected' do
        stub_llm(approved_payload.merge('generalizavel' => { 'aprovado' => false, 'motivo' => 'contém preço negociado' }))

        result = judge(answer: 'Pra você faço por 180 reais.')
        expect(result[:answer]).to eq('Pra você faço por 180 reais.')
      end
    end

    describe 'revision safety' do
      it 'accepts a revision that only changes wording' do
        stub_llm(approved_payload.merge('resposta_revisada' => 'Não aceitamos pets em nenhuma das unidades.'))

        expect(judge[:answer]).to eq('Não aceitamos pets em nenhuma das unidades.')
      end

      it 'discards a revision that shrinks the answer beyond the safe ratio' do
        stub_llm(approved_payload.merge('resposta_revisada' => 'Não.'))

        expect(judge[:answer]).to eq('Não aceitamos animais em nenhuma unidade.')
      end

      it 'discards a revision that inflates the answer beyond the safe ratio' do
        stub_llm(approved_payload.merge('resposta_revisada' => 'Não aceitamos animais. ' * 40))

        expect(judge[:answer]).to eq('Não aceitamos animais em nenhuma unidade.')
      end

      it 'keeps the original when the revision is blank' do
        stub_llm(approved_payload.merge('resposta_revisada' => ''))

        expect(judge[:answer]).to eq('Não aceitamos animais em nenhuma unidade.')
      end
    end

    context 'when the judge returns invalid JSON' do
      before do
        allow(RubyLLM).to receive(:chat).and_return(mock_chat)
        allow(mock_chat).to receive(:with_temperature).and_return(mock_chat)
        allow(mock_chat).to receive(:with_params).and_return(mock_chat)
        allow(mock_chat).to receive(:ask).and_return(instance_double(RubyLLM::Message, content: 'not json'))
      end

      it 'rejects without raising, so the FAQ stays pending' do
        result = judge

        expect(result[:approved]).to be(false)
        expect(result[:raw]['erro']).to match(/json_parse_error/)
      end
    end

    context 'when the LLM call blows up' do
      before do
        allow(RubyLLM).to receive(:chat).and_raise(StandardError, 'boom')
      end

      it 'rejects without raising and records the error' do
        result = judge

        expect(result[:approved]).to be(false)
        expect(result[:raw]['erro']).to match(/llm_error/)
      end
    end

    context 'with existing knowledge as neighbours' do
      let(:neighbour) do
        create(:captain_assistant_response, assistant: assistant, question: 'Aceita pet?', answer: 'Aceitamos cães pequenos.')
      end

      it 'sends the neighbour into the prompt so contradiction can be judged' do
        stub_llm(approved_payload)
        expect(mock_chat).to receive(:ask).with(/Aceitamos cães pequenos/).and_return(
          instance_double(RubyLLM::Message, content: approved_payload.to_json)
        )

        judge(neighbours: [neighbour])
      end
    end
  end

  describe '.judge_model' do
    it 'prefers the configured judge model' do
      create(:installation_config, name: 'CAPTAIN_JUDGE_MODEL', value: 'gpt-judge-test')

      expect(described_class.judge_model).to eq('gpt-judge-test')
    end

    it 'falls back to the light model when unset' do
      expect(described_class.judge_model).to eq(Captain::Llm::ProviderConfig.light_model)
    end
  end
end
