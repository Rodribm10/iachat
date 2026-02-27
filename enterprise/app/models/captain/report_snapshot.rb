# == Schema Information
#
# Table name: captain_report_snapshots
#
#  id              :bigint           not null, primary key
#  account_id      :bigint           not null
#  captain_unit_id :bigint
#  snapshot_date   :date             not null
#  data            :jsonb            not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#

class Captain::ReportSnapshot < ApplicationRecord
  belongs_to :account
  belongs_to :captain_unit, class_name: 'Captain::Unit', optional: true

  validates :snapshot_date, presence: true

  scope :for_unit, ->(unit_id) { where(captain_unit_id: unit_id) }
  scope :for_period, ->(start_date, end_date) { where(snapshot_date: start_date..end_date) }
  scope :recent, -> { order(snapshot_date: :desc) }
end
