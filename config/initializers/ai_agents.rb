# frozen_string_literal: true

require 'agents'

Rails.application.config.after_initialize do
  settings = Captain::Llm::ProviderConfig.settings
  next if settings[:api_key].blank?

  Agents.configure do |config|
    config.openai_api_key = settings[:api_key]
    config.openai_api_base = "#{settings[:api_base]}/v1" if settings[:api_base].present?
    config.default_model = settings[:model]
    config.debug = false
  end
rescue StandardError => e
  Rails.logger.error "Failed to configure AI Agents SDK: #{e.message}"
end
