# == Schema Information
#
# Table name: captain_conversation_insights
#
#  id                  :bigint           not null, primary key
#  account_id          :bigint           not null
#  captain_unit_id     :bigint
#  period_start        :date             not null
#  period_end          :date             not null
#  status              :string           default("pending"), not null
#  payload             :jsonb
#  conversations_count :integer          default(0)
#  messages_count      :integer          default(0)
#  llm_tokens_used     :integer
#  generated_at        :datetime
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
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
