require 'ruby_llm'

module Llm::Config
  DEFAULT_MODEL = Captain::Llm::ProviderConfig::DEFAULT_MODEL

  class << self
    def initialized?
      @initialized ||= false
    end

    def initialize!
      return if @initialized

      configure_ruby_llm
      @initialized = true
    end

    def reset!
      @initialized = false
    end

    def with_api_key(api_key, api_base: nil)
      context = RubyLLM.context do |config|
        config.openai_api_key = api_key
        config.openai_api_base = api_base
      end

      yield context
    end

    private

    def configure_ruby_llm
      settings = Captain::Llm::ProviderConfig.settings

      RubyLLM.configure do |config|
        config.openai_api_key = settings[:api_key] if settings[:api_key].present?
        config.openai_api_base = "#{settings[:api_base]}/v1" if settings[:api_base].present?
        config.logger = Rails.logger
      end
    end
  end
end
