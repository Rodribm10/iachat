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

    context 'when provider is openai_hermes_gateway' do
      before do
        InstallationConfig.create!(name: 'CAPTAIN_LLM_PROVIDER', value: 'openai_hermes_gateway')
        InstallationConfig.create!(name: 'CAPTAIN_HERMES_GATEWAY_URL', value: 'http://host.docker.internal:9877')
        InstallationConfig.create!(name: 'CAPTAIN_HERMES_GATEWAY_MODEL', value: 'anthropic/claude-opus-4-5')
      end

      it 'returns the gateway URL with dummy api_key when no key is configured' do
        settings = described_class.settings
        expect(settings[:api_key]).to eq(described_class::HERMES_GATEWAY_DUMMY_KEY)
        expect(settings[:api_base]).to eq('http://host.docker.internal:9877')
        expect(settings[:model]).to eq('anthropic/claude-opus-4-5')
      end

      it 'honors CAPTAIN_HERMES_GATEWAY_API_KEY when present' do
        InstallationConfig.create!(name: 'CAPTAIN_HERMES_GATEWAY_API_KEY', value: 'sk-hermes-real')
        expect(described_class.settings[:api_key]).to eq('sk-hermes-real')
      end

      it 'honors a custom CAPTAIN_HERMES_GATEWAY_MODEL value' do
        InstallationConfig.find_by!(name: 'CAPTAIN_HERMES_GATEWAY_MODEL').update!(value: 'openai/gpt-5.4')
        expect(described_class.settings[:model]).to eq('openai/gpt-5.4')
      end

      it 'reports hermes_gateway? as true and codex_oauth? as false' do
        expect(described_class.hermes_gateway?).to be true
        expect(described_class.codex_oauth?).to be false
      end

      it 'strips trailing slash from gateway URL' do
        InstallationConfig.find_by!(name: 'CAPTAIN_HERMES_GATEWAY_URL').update!(value: 'http://host.docker.internal:9877/')
        expect(described_class.settings[:api_base]).to eq('http://host.docker.internal:9877')
      end

      it 'uses default model when CAPTAIN_HERMES_GATEWAY_MODEL is missing' do
        InstallationConfig.find_by!(name: 'CAPTAIN_HERMES_GATEWAY_MODEL').delete
        expect(described_class.settings[:model]).to eq(described_class::DEFAULT_HERMES_GATEWAY_MODEL)
      end

      it 'uses default URL when CAPTAIN_HERMES_GATEWAY_URL is missing' do
        InstallationConfig.find_by!(name: 'CAPTAIN_HERMES_GATEWAY_URL').delete
        expect(described_class.settings[:api_base]).to eq(described_class::DEFAULT_HERMES_GATEWAY_URL)
      end
    end

    context 'when default provider (openai_api) is in use' do
      it 'reports hermes_gateway? as false' do
        expect(described_class.hermes_gateway?).to be false
      end
    end

    describe '.light_model' do
      it 'returns gpt-4o-mini for openai_api' do
        expect(described_class.light_model).to eq('gpt-4o-mini')
      end

      it 'returns DEFAULT_CODEX_MODEL for openai_codex_oauth' do
        InstallationConfig.create!(name: 'CAPTAIN_LLM_PROVIDER', value: 'openai_codex_oauth')
        expect(described_class.light_model).to eq(described_class::DEFAULT_CODEX_MODEL)
      end

      it 'returns DEFAULT_HERMES_GATEWAY_MODEL for openai_hermes_gateway' do
        InstallationConfig.create!(name: 'CAPTAIN_LLM_PROVIDER', value: 'openai_hermes_gateway')
        expect(described_class.light_model).to eq(described_class::DEFAULT_HERMES_GATEWAY_MODEL)
      end
    end
  end
end
