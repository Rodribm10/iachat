# Single source of truth para a configuração do provider LLM do Captain.
#
# Lê CAPTAIN_LLM_PROVIDER e retorna a combinação certa de (api_key, api_base, model):
#
# - openai_api (padrão): usa CAPTAIN_OPEN_AI_API_KEY + CAPTAIN_OPEN_AI_ENDPOINT.
#   Mesmo comportamento legado.
#
# - openai_codex_oauth: aponta para o proxy interno
#   (CAPTAIN_CODEX_PROXY_URL, default http://localhost:3000/codex) e usa uma
#   api_key dummy — o proxy ignora o Authorization header e usa OAuth interno.
#
# O "legacy" ruby-openai usado para PDF/Files API NÃO deve usar esse módulo:
# o endpoint Codex não expõe Files API, então esses serviços continuam
# apontando sempre para OpenAI tradicional.
class Captain::Llm::ProviderConfig
  DEFAULT_MODEL = 'gpt-4.1-mini'.freeze
  DEFAULT_OPENAI_ENDPOINT = 'https://api.openai.com'.freeze
  DEFAULT_CODEX_PROXY_URL = 'http://localhost:3000/codex'.freeze
  DUMMY_API_KEY = 'codex-oauth'.freeze

  class << self
    def provider
      cfg('CAPTAIN_LLM_PROVIDER').presence || 'openai_api'
    end

    def codex_oauth?
      provider == 'openai_codex_oauth'
    end

    # Retorna { api_key:, api_base:, model: } para RubyLLM/Agents.
    def settings
      if codex_oauth?
        codex_settings
      else
        openai_api_settings
      end
    end

    def api_key
      settings[:api_key]
    end

    # Base URL "crua", sem /v1. O cliente (ai_agents.rb) adiciona /v1.
    def api_base
      settings[:api_base]
    end

    def model
      settings[:model]
    end

    private

    def codex_settings
      {
        api_key: DUMMY_API_KEY,
        api_base: (cfg('CAPTAIN_CODEX_PROXY_URL').presence || DEFAULT_CODEX_PROXY_URL).chomp('/'),
        model: cfg('CAPTAIN_OPEN_AI_MODEL').presence || default_codex_model
      }
    end

    def openai_api_settings
      {
        api_key: cfg('CAPTAIN_OPEN_AI_API_KEY'),
        api_base: (cfg('CAPTAIN_OPEN_AI_ENDPOINT').presence || DEFAULT_OPENAI_ENDPOINT).chomp('/'),
        model: cfg('CAPTAIN_OPEN_AI_MODEL').presence || DEFAULT_MODEL
      }
    end

    def default_codex_model
      'gpt-5.4'
    end

    def cfg(name)
      InstallationConfig.find_by(name: name)&.value
    end
  end
end
