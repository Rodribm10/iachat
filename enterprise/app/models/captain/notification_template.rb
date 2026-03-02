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
#  inbox_id         :bigint           not null
#
# Indexes
#
#  idx_notif_templates_inbox_active  (inbox_id,active)
#
# Foreign Keys
#
#  fk_rails_...  (inbox_id => inboxes.id)
#
class Captain::NotificationTemplate < ApplicationRecord
  self.table_name = 'captain_notification_templates'

  belongs_to :inbox, inverse_of: :captain_notification_templates

  enum timing_direction: { before: 0, after: 1 }

  validates :label, presence: true
  validates :content, presence: true
  validates :timing_minutes, presence: true, numericality: { greater_than: 0 }
  validates :timing_direction, presence: true
  validates :inbox_id, presence: true

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(:position, :id) }
  scope :for_inbox, ->(inbox_id) { where(inbox_id: inbox_id) }
end
