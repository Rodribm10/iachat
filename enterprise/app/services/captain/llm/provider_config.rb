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

  # Modelo padrão pro Codex. gpt-5.2 é o mais recente reconhecido pelo RubyLLM
  # (gpt-5.4 ainda não está no catalog do gem). Ambos são suportados pelo
  # endpoint Codex da OpenAI via ChatGPT Plus.
  DEFAULT_CODEX_MODEL = 'gpt-5.2'.freeze

  # Modelo leve pra tasks de background (extração de memória, verificação de
  # contradição, traduções internas). Quando usamos Codex, reutilizamos o
  # mesmo modelo do chat — o endpoint não expõe gpt-4o-mini.
  LIGHT_MODEL_DEFAULTS = {
    'openai_api' => 'gpt-4o-mini',
    'openai_codex_oauth' => DEFAULT_CODEX_MODEL
  }.freeze

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

    # Modelo pra tasks leves (memory extraction, contradiction check, etc).
    # Respeita a flag de provider: em Codex OAuth, usa o mesmo modelo do chat.
    def light_model
      LIGHT_MODEL_DEFAULTS[provider] || LIGHT_MODEL_DEFAULTS['openai_api']
    end

    # Settings sempre da OpenAI tradicional, independente do provider.
    # Usado por recursos que o endpoint Codex NÃO expõe: /embeddings e Files API.
    # Lança AuthError se não houver CAPTAIN_OPEN_AI_API_KEY configurada.
    def legacy_openai_settings
      {
        api_key: cfg('CAPTAIN_OPEN_AI_API_KEY'),
        api_base: (cfg('CAPTAIN_OPEN_AI_ENDPOINT').presence || DEFAULT_OPENAI_ENDPOINT).chomp('/')
      }
    end

    private

    def codex_settings
      {
        api_key: DUMMY_API_KEY,
        api_base: (cfg('CAPTAIN_CODEX_PROXY_URL').presence || DEFAULT_CODEX_PROXY_URL).chomp('/'),
        model: cfg('CAPTAIN_OPEN_AI_MODEL').presence || DEFAULT_CODEX_MODEL
      }
    end

    def openai_api_settings
      {
        api_key: cfg('CAPTAIN_OPEN_AI_API_KEY'),
        api_base: (cfg('CAPTAIN_OPEN_AI_ENDPOINT').presence || DEFAULT_OPENAI_ENDPOINT).chomp('/'),
        model: cfg('CAPTAIN_OPEN_AI_MODEL').presence || DEFAULT_MODEL
      }
    end

    def cfg(name)
      InstallationConfig.find_by(name: name)&.value
    end
  end
end
