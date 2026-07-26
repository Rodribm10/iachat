require 'rails_helper'

# A sonda do OS Foco lê esta rota a cada 30 min. Ela precisa ser fechada por
# padrão: um endpoint de diagnóstico aberto por esquecimento é convite.
RSpec.describe 'Webhooks::Captain::HealthController', type: :request do
  let(:segredo) { 'segredo-de-teste-123' }

  def buscar(token: nil)
    headers = token ? { 'Authorization' => "Bearer #{token}" } : {}
    get '/webhooks/captain/health', headers: headers
  end

  describe 'quando o segredo não está configurado' do
    it 'responde 404 — a rota não existe, em vez de confirmar que existe algo aqui' do
      buscar(token: 'qualquer')

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'quando o segredo está configurado' do
    before { create(:installation_config, name: 'CAPTAIN_HEALTH_SECRET', value: segredo) }

    it 'recusa sem token' do
      buscar

      expect(response).to have_http_status(:unauthorized)
    end

    it 'recusa token errado' do
      buscar(token: 'token-errado')

      expect(response).to have_http_status(:unauthorized)
    end

    it 'devolve o retrato das conexões com o token certo' do
      buscar(token: segredo)

      expect(response).to have_http_status(:success)

      corpo = response.parsed_body
      expect(corpo).to include('referencia', 'resumo', 'conexoes')
      expect(corpo['resumo']).to include('ok', 'critico', 'alertaveis')
      expect(corpo['conexoes'].map { |c| c['chave'] }).to include('codex', 'aprendizado', 'hermes')
    end

    it 'não vaza conteúdo de conversa nem dado de cliente' do
      buscar(token: segredo)

      expect(response.parsed_body['conexoes'].first.keys)
        .to match_array(%w[chave nome status detalhe acao verificado_em])
    end
  end
end
