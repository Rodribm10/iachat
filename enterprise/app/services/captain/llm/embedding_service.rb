class Captain::Llm::EmbeddingService
  include Integrations::LlmInstrumentation

  class EmbeddingsError < StandardError; end

  def initialize(account_id: nil)
    Llm::Config.initialize!
    @account_id = account_id
    @embedding_model = InstallationConfig.find_by(name: 'CAPTAIN_EMBEDDING_MODEL')&.value.presence || LlmConstants::DEFAULT_EMBEDDING_MODEL
  end

  def self.embedding_model
    InstallationConfig.find_by(name: 'CAPTAIN_EMBEDDING_MODEL')&.value.presence || LlmConstants::DEFAULT_EMBEDDING_MODEL
  end

  def get_embedding(content, model: @embedding_model)
    return [] if content.blank?

    instrument_embedding_call(instrumentation_params(content, model)) do
      embed_with_legacy_openai(content, model)
    end
  rescue RubyLLM::Error => e
    Rails.logger.error "Embedding API Error: #{e.message}"
    raise EmbeddingsError, "Failed to create an embedding: #{e.message}"
  end

  private

  # Embeddings vão pra OpenAI tradicional por default (o endpoint Codex
  # via ChatGPT OAuth não expõe /embeddings). Override opcional via env vars
  # dedicadas — útil pra trocar provider de embedding (ex: Gemini
  # OpenAI-compatible) sem alterar o provider de chat:
  #
  #   CAPTAIN_EMBEDDING_API_KEY     — sobrescreve API key
  #   CAPTAIN_EMBEDDING_ENDPOINT    — sobrescreve base URL (sem /v1 no final)
  #   CAPTAIN_EMBEDDING_DIMENSIONS  — força reduction (ex: 1536 pra Gemini
  #                                    bater com schema pgvector(1536))
  def embed_with_legacy_openai(content, model)
    settings = embedding_settings
    api_base = settings[:api_base].present? ? "#{settings[:api_base]}/v1" : nil
    embed_options = embed_extra_options

    Llm::Config.with_api_key(settings[:api_key], api_base: api_base) do |ctx|
      ctx.embed(content, model: model, **embed_options).vectors
    end
  end

  def embedding_settings
    custom_key = installation_config_value('CAPTAIN_EMBEDDING_API_KEY')
    return Captain::Llm::ProviderConfig.legacy_openai_settings if custom_key.blank?

    {
      api_key: custom_key,
      api_base: installation_config_value('CAPTAIN_EMBEDDING_ENDPOINT')&.chomp('/')
    }
  end

  def embed_extra_options
    dims = installation_config_value('CAPTAIN_EMBEDDING_DIMENSIONS')
    return {} if dims.blank?

    { dimensions: dims.to_i }
  end

  def installation_config_value(name)
    ENV.fetch(name, nil) ||
      InstallationConfig.find_by(name: name)&.value
  end

  def instrumentation_params(content, model)
    {
      span_name: 'llm.captain.embedding',
      model: model,
      input: content,
      feature_name: 'embedding',
      account_id: @account_id
    }
  end
end
