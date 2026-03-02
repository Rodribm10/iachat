# == Schema Information
#
# Table name: captain_notification_templates
#
#  id               :bigint           not null, primary key
#  active           :boolean          default(TRUE), not null
#  content          :text             not null
#  label            :string           not null
#  position         :integer          default(0), not null
#  timing_direction :integer          default("before"), not null
#  timing_minutes   :integer          default(10), not null
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  captain_unit_id  :bigint           not null
#
# Indexes
#
#  idx_notif_templates_unit_active                          (captain_unit_id,active)
#  index_captain_notification_templates_on_captain_unit_id  (captain_unit_id)
#
# Foreign Keys
#
#  fk_rails_...  (captain_unit_id => captain_units.id)
#
class Captain::NotificationTemplate < ApplicationRecord
  self.table_name = 'captain_notification_templates'

  belongs_to :unit, class_name: 'Captain::Unit', foreign_key: 'captain_unit_id', inverse_of: :notification_templates

  enum timing_direction: { before: 0, after: 1 }

  validates :label, presence: true
  validates :content, presence: true
  validates :timing_minutes, presence: true, numericality: { greater_than: 0 }
  validates :timing_direction, presence: true
  validates :captain_unit_id, presence: true

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(:position, :id) }
  scope :for_unit, ->(unit_id) { where(captain_unit_id: unit_id) }
end
