require 'rails_helper'

# O conhecimento em quarentena (`trial`) responde ao cliente como qualquer FAQ
# aprovada — é isso que faz o ciclo de aprendizado andar sem aprovação manual.
# O que o juiz reprovou (`pending`) e o que foi aposentado (`retired`) nunca
# pode chegar ao cliente. Aqui a busca vetorial roda de verdade (pgvector).
# rubocop:disable RSpec/DescribeClass
RSpec.describe 'Retrievable knowledge across every Captain lookup path' do
  let(:account) { create(:account) }
  let(:assistant) { create(:captain_assistant, account: account) }

  let!(:approved) do
    create(:captain_assistant_response, assistant: assistant, account: account,
                                        question: 'Qual o horário do check-in?', answer: 'A partir das 14h.',
                                        status: 'approved')
  end
  let!(:trial) do
    create(:captain_assistant_response, assistant: assistant, account: account,
                                        question: 'Vocês aceitam pet?', answer: 'Não aceitamos animais.',
                                        status: 'trial', trial_until: 30.days.from_now, source: 'human_validated')
  end

  before do
    create(:installation_config, name: 'CAPTAIN_OPEN_AI_API_KEY', value: 'test-key')

    create(:captain_assistant_response, assistant: assistant, account: account,
                                        question: 'Tem estacionamento?', answer: 'Reprovada pelo juiz.',
                                        status: 'pending')
    create(:captain_assistant_response, assistant: assistant, account: account,
                                        question: 'Tem piscina?', answer: 'Conhecimento aposentado.',
                                        status: 'retired', retired_at: Time.current)

    embedding_service = instance_double(Captain::Llm::EmbeddingService)
    allow(Captain::Llm::EmbeddingService).to receive(:new).and_return(embedding_service)
    allow(embedding_service).to receive(:get_embedding).and_return(Array.new(1536) { rand(-1.0..1.0) })

    translate_service = instance_double(Captain::Llm::TranslateQueryService)
    allow(Captain::Llm::TranslateQueryService).to receive(:new).and_return(translate_service)
    allow(translate_service).to receive(:translate) { |query, **| query }
  end

  shared_examples 'serves live knowledge only' do
    it 'includes approved knowledge' do
      expect(result).to include(approved.answer)
    end

    it 'includes knowledge still in quarantine' do
      expect(result).to include(trial.answer)
    end

    it 'never leaks knowledge the judge rejected' do
      expect(result).not_to include('Reprovada pelo juiz')
    end

    it 'never leaks retired knowledge' do
      expect(result).not_to include('Conhecimento aposentado')
    end
  end

  describe 'Captain V2 faq_lookup tool' do
    let(:result) do
      Captain::Tools::FaqLookupTool.new(assistant).perform(Struct.new(:state).new({}), query: 'pet')
    end

    it_behaves_like 'serves live knowledge only'
  end

  describe 'Captain legacy search_documentation tool' do
    let(:result) { Captain::Tools::SearchDocumentationService.new(assistant).execute(query: 'pet') }

    it_behaves_like 'serves live knowledge only'
  end

  describe 'Hermes MCP search_reply_documentation' do
    let(:result) do
      Captain::Tools::SearchReplyDocumentationService.new(account: account, assistant: assistant).execute(query: 'pet')
    end

    it_behaves_like 'serves live knowledge only'
  end

  describe 'Hermes MCP search_reply_documentation without an assistant' do
    let(:result) do
      Captain::Tools::SearchReplyDocumentationService.new(account: account).execute(query: 'pet')
    end

    it_behaves_like 'serves live knowledge only'
  end

  # O bloco 'FAQ guardrail fallback in the agent runner' saiu em 22/08/2026
  # junto com Captain::Assistant::AgentRunnerService — o motor interno do
  # Captain foi desligado e o Hermes virou o único caminho de resposta. A
  # garantia de que conhecimento reprovado/aposentado não é servido continua
  # coberta pelos exemplos 'serves live knowledge only' acima, que testam a
  # fonte e não o consumidor.
end
# rubocop:enable RSpec/DescribeClass
