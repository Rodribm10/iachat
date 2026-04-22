require 'rails_helper'

RSpec.describe Captain::Llm::ProviderConfig do
  before do
    InstallationConfig.delete_all
  end

  describe '.settings' do
    context 'when provider is openai_api (default)' do
      before do
        InstallationConfig.create!(name: 'CAPTAIN_OPEN_AI_API_KEY', value: 'sk-real')
        InstallationConfig.create!(name: 'CAPTAIN_OPEN_AI_ENDPOINT', value: 'https://api.openai.com')
        InstallationConfig.create!(name: 'CAPTAIN_OPEN_AI_MODEL', value: 'gpt-4o-mini')
      end

      it 'returns the traditional OpenAI API settings' do
        settings = described_class.settings
        expect(settings[:api_key]).to eq('sk-real')
        expect(settings[:api_base]).to eq('https://api.openai.com')
        expect(settings[:model]).to eq('gpt-4o-mini')
      end

      it 'reports codex_oauth? as false' do
        expect(described_class.codex_oauth?).to be false
      end
    end

    context 'when provider is openai_codex_oauth' do
      before do
        InstallationConfig.create!(name: 'CAPTAIN_LLM_PROVIDER', value: 'openai_codex_oauth')
        InstallationConfig.create!(name: 'CAPTAIN_CODEX_PROXY_URL', value: 'http://localhost:3000/codex')
      end

      it 'returns the proxy settings with a dummy key' do
        settings = described_class.settings
        expect(settings[:api_key]).to eq(described_class::DUMMY_API_KEY)
        expect(settings[:api_base]).to eq('http://localhost:3000/codex')
      end

      it 'falls back to DEFAULT_CODEX_MODEL when no custom model is set' do
        expect(described_class.settings[:model]).to eq(described_class::DEFAULT_CODEX_MODEL)
      end

      it 'honors CAPTAIN_OPEN_AI_MODEL override even with Codex OAuth' do
        InstallationConfig.create!(name: 'CAPTAIN_OPEN_AI_MODEL', value: 'gpt-5.4-mini')
        expect(described_class.settings[:model]).to eq('gpt-5.4-mini')
      end

      it 'reports codex_oauth? as true' do
        expect(described_class.codex_oauth?).to be true
      end

      it 'strips trailing slash from proxy URL' do
        InstallationConfig.find_by!(name: 'CAPTAIN_CODEX_PROXY_URL').update!(value: 'http://localhost:3000/codex/')
        expect(described_class.settings[:api_base]).to eq('http://localhost:3000/codex')
      end
    end

    context 'when CAPTAIN_CODEX_PROXY_URL is missing' do
      before { InstallationConfig.create!(name: 'CAPTAIN_LLM_PROVIDER', value: 'openai_codex_oauth') }

      it 'falls back to the default localhost URL' do
        expect(described_class.settings[:api_base]).to eq(described_class::DEFAULT_CODEX_PROXY_URL)
      end
    end
  end
end
