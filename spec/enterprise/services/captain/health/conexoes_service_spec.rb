require 'rails_helper'

RSpec.describe Captain::Health::ConexoesService do
  let(:account) { create(:account) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:embedding_service) { instance_double(Captain::Llm::EmbeddingService) }

  before do
    allow(Captain::Llm::EmbeddingService).to receive(:new).and_return(embedding_service)
    allow(embedding_service).to receive(:get_embedding).and_return(Array.new(1536, 0.1))
  end

  def conexao(chave)
    described_class.new.call[:conexoes].find { |c| c[:chave] == chave }
  end

  describe 'verificação de embeddings' do
    it 'reporta ok quando gera vetor e não há FAQ órfã' do
      create(:captain_assistant_response, assistant: assistant, status: 'approved')

      c = conexao('embeddings')

      expect(c[:status]).to eq('ok')
      expect(c[:detalhe]).to include('1536')
    end

    # O caso real de 05/08/2026: a cota do provedor estourou e o ciclo morreu
    # por 8 dias. O sensor via o sintoma mas apontava a causa errada.
    it 'reporta crítico e o motivo real quando a cota do provedor estoura' do
      allow(embedding_service).to receive(:get_embedding)
        .and_raise(Captain::Llm::EmbeddingService::EmbeddingsError,
                   'Your project has exceeded its monthly spending cap')

      c = conexao('embeddings')

      expect(c[:status]).to eq('critico')
      expect(c[:detalhe]).to include('exceeded its monthly spending cap')
      expect(c[:acao]).to include('cota')
    end

    it 'reporta crítico quando o serviço devolve vetor vazio' do
      allow(embedding_service).to receive(:get_embedding).and_return([])

      expect(conexao('embeddings')[:status]).to eq('critico')
    end

    it 'alerta quando há FAQ sem embedding, invisível na busca' do
      create(:captain_assistant_response, assistant: assistant, status: 'approved', embedding: nil)

      c = conexao('embeddings')

      expect(c[:status]).to eq('alerta')
      expect(c[:detalhe]).to include('invisíveis na busca')
    end
  end

  describe 'diagnóstico da captura' do
    # Antes este texto chutava "credencial de IA é a causa mais comum" — e na
    # única vez que importou, o chute estava errado: a IA estava perfeita e
    # quem tinha caído era o embedding.
    it 'não chuta a causa: manda olhar as outras conexões' do
      inbox = create(:inbox, account: account)
      create(:conversation, account: account, inbox: inbox, status: :resolved,
                            first_reply_created_at: 1.day.ago, updated_at: 1.day.ago)

      c = conexao('aprendizado')

      expect(c[:status]).to eq('critico')
      expect(c[:detalhe]).not_to include('credencial')
      expect(c[:acao]).to include('Embeddings')
    end
  end

  describe 'resumo' do
    it 'conta o que é alertável, com embeddings entre as conexões' do
      resultado = described_class.new.call

      expect(resultado[:conexoes].map { |c| c[:chave] })
        .to include('codex', 'embeddings', 'aprendizado', 'hermes', 'inter')
      expect(resultado[:resumo]).to include(:total, :ok, :alerta, :critico, :indisponivel, :alertaveis)
    end
  end
end
