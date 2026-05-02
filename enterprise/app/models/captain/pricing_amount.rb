# == Schema Information
#
# Table name: captain_pricing_amounts
#
#  id                          :bigint           not null, primary key
#  amount                      :decimal(10, 2)   not null
#  day_bucket                  :string
#  period                      :string           not null
#  created_at                  :datetime         not null
#  updated_at                  :datetime         not null
#  captain_pricing_category_id :bigint           not null
#
# Indexes
#
#  idx_captain_pricing_amount_uniq                               (captain_pricing_category_id,period,day_bucket) UNIQUE
#  index_captain_pricing_amounts_on_captain_pricing_category_id  (captain_pricing_category_id)
#
# Foreign Keys
#
#  fk_rails_...  (captain_pricing_category_id => captain_pricing_categories.id)
#
# Valor por (categoria, período, dia da semana). day_bucket NULL = preço
# único todos os dias. day_bucket='mon_wed' = seg-qua. 'thu_sun' = qui-dom.
class Captain::PricingAmount < ApplicationRecord
  self.table_name = 'captain_pricing_amounts'

  PERIODS = %w[1h 2h 3h 4h 5h pernoite_promo pernoite_integral diaria].freeze
  DAY_BUCKETS = %w[mon_wed thu_sun].freeze

  belongs_to :pricing_category,
             class_name: 'Captain::PricingCategory',
             foreign_key: :captain_pricing_category_id,
             inverse_of: :amounts

  validates :period, inclusion: { in: PERIODS }
  validates :day_bucket, inclusion: { in: DAY_BUCKETS, allow_nil: true }
  validates :amount, numericality: { greater_than: 0 }
  validates :captain_pricing_category_id,
            uniqueness: { scope: %i[period day_bucket] }
end
