class Captain::UnitInbox < ApplicationRecord
  self.table_name = 'captain_unit_inboxes'

  belongs_to :captain_unit, class_name: 'Captain::Unit'
  belongs_to :inbox

  validates :captain_unit_id, uniqueness: { scope: :inbox_id }
end
