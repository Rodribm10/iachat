# frozen_string_literal: true

# == Schema Information
#
# Table name: captain_brands
#
#  id                  :bigint           not null, primary key
#  name                :string           not null
#  pricing_page_config :jsonb            not null
#  stay_durations      :jsonb            not null
#  suite_categories    :jsonb            not null
#  suite_descriptions  :jsonb            not null
#  suite_images        :jsonb            not null
#  suite_keywords      :jsonb
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  account_id          :bigint           not null
#
# Indexes
#
#  index_captain_brands_on_account_id  (account_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#
class Captain::Brand < ApplicationRecord
  self.table_name = 'captain_brands'

  attribute :suite_keywords, :jsonb, default: -> { {} }
  attribute :suite_descriptions, :jsonb, default: -> { {} }
  attribute :pricing_page_config, :jsonb, default: -> { {} }

  belongs_to :account
  has_many :units, class_name: 'Captain::Unit', foreign_key: 'captain_brand_id', dependent: :destroy
  has_many :pricings, class_name: 'Captain::Pricing', foreign_key: 'captain_brand_id', dependent: :destroy
  has_many :reservations, class_name: 'Captain::Reservation', foreign_key: 'captain_brand_id'

  validates :name, presence: true

  def pricing_page_enabled?
    pricing_page_config['enabled'] == true
  end
end
