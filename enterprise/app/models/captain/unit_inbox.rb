# == Schema Information
#
# Table name: captain_unit_inboxes
#
#  id              :bigint           not null, primary key
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  captain_unit_id :bigint           not null
#  inbox_id        :bigint           not null
#
# Indexes
#
#  index_captain_unit_inboxes_on_inbox_id        (inbox_id)
#  index_captain_unit_inboxes_on_unit_and_inbox  (captain_unit_id,inbox_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (captain_unit_id => captain_units.id) ON DELETE => cascade
#  fk_rails_...  (inbox_id => inboxes.id) ON DELETE => cascade
#
class Captain::UnitInbox < ApplicationRecord
  self.table_name = 'captain_unit_inboxes'

  belongs_to :captain_unit, class_name: 'Captain::Unit'
  belongs_to :inbox

  validates :captain_unit_id, uniqueness: { scope: :inbox_id }
end
