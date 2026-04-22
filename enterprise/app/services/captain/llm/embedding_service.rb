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

  # Embeddings sempre vão direto pra OpenAI tradicional — o endpoint Codex
  # via ChatGPT OAuth não expõe /embeddings.
  def embed_with_legacy_openai(content, model)
    legacy = Captain::Llm::ProviderConfig.legacy_openai_settings
    api_base = legacy[:api_base].present? ? "#{legacy[:api_base]}/v1" : nil

    Llm::Config.with_api_key(legacy[:api_key], api_base: api_base) do |ctx|
      ctx.embed(content, model: model).vectors
    end
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
