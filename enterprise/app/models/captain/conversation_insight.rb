# == Schema Information
#
# Table name: captain_conversation_insights
#
#  id                  :bigint           not null, primary key
#  conversations_count :integer          default(0)
#  generated_at        :datetime
#  llm_tokens_used     :integer
#  messages_count      :integer          default(0)
#  payload             :jsonb
#  period_end          :date             not null
#  period_start        :date             not null
#  status              :string           default("pending"), not null
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  account_id          :bigint           not null
#  captain_unit_id     :bigint
#  inbox_id            :bigint
#
# Indexes
#
#  idx_captain_insights_on_unit_inbox_period                     (captain_unit_id,inbox_id,period_start,period_end) UNIQUE
#  index_captain_conversation_insights_on_account_id             (account_id)
#  index_captain_conversation_insights_on_account_id_and_status  (account_id,status)
#  index_captain_conversation_insights_on_captain_unit_id        (captain_unit_id)
#  index_captain_conversation_insights_on_inbox_id               (inbox_id)
#
# Foreign Keys
#
#  fk_rails_...       (account_id => accounts.id)
#  fk_rails_...       (captain_unit_id => captain_units.id)
#  fk_rails_inbox_id  (inbox_id => inboxes.id)
#

class Captain::ConversationInsight < ApplicationRecord
  include Rails.application.routes.url_helpers

  self.table_name = 'captain_conversation_insights'

  STATUSES = %w[pending processing done failed].freeze

  belongs_to :account
  belongs_to :captain_unit, class_name: 'Captain::Unit', optional: true
  belongs_to :inbox, optional: true

  validates :period_start, :period_end, :status, presence: true
  validates :status, inclusion: { in: STATUSES }

  scope :done, -> { where(status: 'done') }
  scope :for_unit, ->(unit_id) { where(captain_unit_id: unit_id) }
  scope :for_inbox, ->(inbox_id) { where(inbox_id: inbox_id) }
  scope :for_period, ->(start_date, end_date) { where(period_start: start_date, period_end: end_date) }

  def mark_processing!
    update!(status: 'processing')
  end

  def mark_done!(payload, tokens_used: nil)
    update!(
      status: 'done',
      payload: payload,
      llm_tokens_used: tokens_used,
      generated_at: Time.current
    )
  end

  def mark_failed!
    update!(status: 'failed')
  end

  def pending?
    status == 'pending'
  end

  def processing?
    status == 'processing'
  end

  def done?
    status == 'done'
  end
end
