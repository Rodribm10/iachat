# == Schema Information
#
# Table name: captain_pricing_categories
#
#  id                     :bigint           not null, primary key
#  aliases                :jsonb            not null
#  extra_person_starts_at :integer          default(3), not null
#  key                    :string           not null
#  created_at             :datetime         not null
#  updated_at             :datetime         not null
#  captain_unit_id        :bigint           not null
#
# Indexes
#
#  index_captain_pricing_categories_on_captain_unit_id          (captain_unit_id)
#  index_captain_pricing_categories_on_captain_unit_id_and_key  (captain_unit_id,key) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (captain_unit_id => captain_units.id)
#
# Categoria de preço por unidade — espelha o que tava em PricingTables.rb
# como Ruby hash. `key` é canônico ('apartamento', 'standard', etc),
# `aliases` é array de strings que o LLM pode digitar e bate via fuzzy
# match. `extra_person_starts_at` controla a partir de qual hóspede a taxa
# extra começa (default 3 = casal incluso).
class Captain::PricingCategory < ApplicationRecord
  self.table_name = 'captain_pricing_categories'

  belongs_to :captain_unit, class_name: 'Captain::Unit', inverse_of: :pricing_categories
  has_many :amounts,
           class_name: 'Captain::PricingAmount',
           foreign_key: :captain_pricing_category_id,
           inverse_of: :pricing_category,
           dependent: :destroy

  validates :key, presence: true, uniqueness: { scope: :captain_unit_id }
  validates :extra_person_starts_at, numericality: { greater_than_or_equal_to: 1 }
  validate :aliases_is_array

  def matches?(needle)
    return false if needle.blank?

    candidates = ([key.to_s.tr('_', ' ')] + aliases.to_a).map { |s| s.to_s.downcase.strip }
    candidates.include?(needle.to_s.downcase.strip.tr('_', ' ').squeeze(' '))
  end

  private

  def aliases_is_array
    return if aliases.is_a?(Array)

    errors.add(:aliases, 'must be an array')
  end
end
