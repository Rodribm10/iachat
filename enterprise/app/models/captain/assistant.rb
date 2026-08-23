# == Schema Information
#
# Table name: captain_assistants
#
#  id                         :bigint           not null, primary key
#  api_key                    :text
#  config                     :jsonb            not null
#  description                :string
#  engine                     :string           default("captain_interno"), not null
#  guardrails                 :jsonb
#  handoff_webhook_config     :jsonb
#  hermes_port                :integer
#  hermes_profile_name        :string
#  hermes_subscription_secret :string
#  hermes_webhook_base_url    :string
#  llm_model                  :string           default("gpt-3.5-turbo")
#  llm_provider               :string           default("openai")
#  name                       :string           not null
#  orchestrator_prompt        :text
#  response_guidelines        :jsonb
#  created_at                 :datetime         not null
#  updated_at                 :datetime         not null
#  account_id                 :bigint           not null
#  captain_unit_id            :bigint
#  parent_assistant_id        :bigint
#
# Indexes
#
#  idx_captain_assistants_hermes_port_unique        (hermes_port) UNIQUE WHERE (hermes_port IS NOT NULL)
#  index_captain_assistants_on_account_id           (account_id)
#  index_captain_assistants_on_captain_unit_id      (captain_unit_id)
#  index_captain_assistants_on_engine               (engine)
#  index_captain_assistants_on_parent_assistant_id  (parent_assistant_id)
#
# Foreign Keys
#
#  fk_rails_...  (captain_unit_id => captain_units.id) ON DELETE => nullify
#
class Captain::Assistant < ApplicationRecord
  include Avatarable
  include Concerns::CaptainToolsHelpers

  self.table_name = 'captain_assistants'

  belongs_to :account
  belongs_to :captain_unit, class_name: 'Captain::Unit', optional: true
  has_many :documents, class_name: 'Captain::Document', dependent: :destroy_async
  has_many :responses, class_name: 'Captain::AssistantResponse', dependent: :destroy_async
  has_many :captain_inboxes,
           class_name: 'CaptainInbox',
           foreign_key: :captain_assistant_id,
           dependent: :destroy_async
  has_many :inboxes,
           through: :captain_inboxes
  has_many :messages, as: :sender, dependent: :nullify
  has_many :copilot_threads, dependent: :destroy_async
  has_many :scenarios, class_name: 'Captain::Scenario', dependent: :destroy_async

  store_accessor :config, :temperature, :feature_faq, :feature_memory, :feature_contact_attributes, :product_name

  ENGINES = %w[captain_interno hermes].freeze

  validates :name, presence: true
  validates :description, presence: true
  validates :account_id, presence: true
  validates :engine, inclusion: { in: ENGINES }
  validates :hermes_profile_name, presence: true, if: :hermes?
  validates :hermes_webhook_base_url, presence: true, if: :hermes?

  scope :hermes, -> { where(engine: 'hermes') }
  scope :captain_interno, -> { where(engine: 'captain_interno') }

  scope :ordered, -> { order(created_at: :desc) }

  scope :for_account, ->(account_id) { where(account_id: account_id) }

  def available_name
    name
  end

  def hermes?
    engine == 'hermes'
  end

  def captain_interno?
    engine == 'captain_interno'
  end

  def available_agent_tools
    tools = self.class.built_in_agent_tools.dup

    custom_tools = account.captain_custom_tools.enabled.map(&:to_tool_metadata)
    tools.concat(custom_tools)

    tools
  end

  def available_tool_ids
    available_agent_tools.pluck(:id)
  end

  def pubsub_token
    nil
  end

  def push_event_data
    {
      id: id,
      name: name,
      avatar_url: avatar_url.presence || default_avatar_url,
      description: description,
      created_at: created_at,
      type: 'captain_assistant'
    }
  end

  def webhook_data
    {
      id: id,
      name: name,
      avatar_url: avatar_url.presence || default_avatar_url,
      description: description,
      created_at: created_at,
      type: 'captain_assistant'
    }
  end

  private

  def default_avatar_url
    "#{ENV.fetch('FRONTEND_URL', nil)}/assets/images/dashboard/captain/logo.svg"
  end
end
