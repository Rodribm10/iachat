# == Schema Information
#
# Table name: captain_inboxes
#
#  id                       :bigint           not null, primary key
#  always_use_reminder_tool :boolean          default(FALSE), not null
#  created_at               :datetime         not null
#  updated_at               :datetime         not null
#  captain_assistant_id     :bigint           not null
#  captain_unit_id          :bigint
#  inbox_id                 :bigint           not null
#
# Indexes
#
#  index_captain_inboxes_on_captain_assistant_id               (captain_assistant_id)
#  index_captain_inboxes_on_captain_assistant_id_and_inbox_id  (captain_assistant_id,inbox_id) UNIQUE
#  index_captain_inboxes_on_captain_unit_id                    (captain_unit_id)
#  index_captain_inboxes_on_inbox_id                           (inbox_id)
#
# Foreign Keys
#
#  fk_rails_...  (captain_unit_id => captain_units.id)
#
class CaptainInbox < ApplicationRecord
  belongs_to :captain_assistant, class_name: 'Captain::Assistant'
  belongs_to :inbox
  belongs_to :captain_unit, class_name: 'Captain::Unit', optional: true

  validates :inbox_id, uniqueness: true
end
