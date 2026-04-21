# == Schema Information
#
# Table name: captain_lifecycle_deliveries
#
#  id                     :bigint           not null, primary key
#  failure_reason         :text
#  fire_at                :datetime         not null
#  origin                 :string           default("scheduled_lifecycle"), not null
#  rendered_body          :text
#  sent_at                :datetime
#  skip_reason            :string
#  status                 :string           default("scheduled"), not null
#  created_at             :datetime         not null
#  updated_at             :datetime         not null
#  account_id             :bigint           not null
#  captain_reservation_id :bigint           not null
#  conversation_id        :bigint
#  inbox_id               :bigint
#  lifecycle_rule_id      :bigint
#  message_id             :bigint
#
# Indexes
#
#  idx_lifecycle_deliveries_cap_check                     (captain_reservation_id,origin,status)
#  idx_lifecycle_deliveries_dashboard                     (account_id,status,fire_at)
#  idx_lifecycle_deliveries_reservation                   (captain_reservation_id)
#  idx_lifecycle_deliveries_rule                          (lifecycle_rule_id)
#  idx_lifecycle_deliveries_scheduled                     (fire_at) WHERE ((status)::text = 'scheduled'::text)
#  index_captain_lifecycle_deliveries_on_account_id       (account_id)
#  index_captain_lifecycle_deliveries_on_conversation_id  (conversation_id)
#  index_captain_lifecycle_deliveries_on_inbox_id         (inbox_id)
#  index_captain_lifecycle_deliveries_on_message_id       (message_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (captain_reservation_id => captain_reservations.id)
#  fk_rails_...  (conversation_id => conversations.id)
#  fk_rails_...  (inbox_id => inboxes.id)
#  fk_rails_...  (lifecycle_rule_id => captain_lifecycle_rules.id)
#  fk_rails_...  (message_id => messages.id)
#
class Captain::Lifecycle::Delivery < ApplicationRecord
  self.table_name = 'captain_lifecycle_deliveries'

  STATUSES = %w[scheduled sent skipped failed cancelled].freeze

  belongs_to :account
  belongs_to :lifecycle_rule, class_name: 'Captain::Lifecycle::Rule', optional: true
  belongs_to :captain_reservation, class_name: 'Captain::Reservation'
  belongs_to :conversation, class_name: '::Conversation', optional: true
  belongs_to :message, optional: true
  belongs_to :inbox, optional: true

  validates :fire_at, presence: true
  validates :status, inclusion: { in: STATUSES }

  scope :scheduled, -> { where(status: 'scheduled') }
  scope :sent, -> { where(status: 'sent') }
  scope :skipped, -> { where(status: 'skipped') }
  scope :for_reservation, ->(id) { where(captain_reservation_id: id) }

  def self.count_sent_for_reservation(reservation_id)
    for_reservation(reservation_id)
      .where(status: 'sent', origin: 'scheduled_lifecycle')
      .count
  end

  def mark_skipped!(reason)
    update!(status: 'skipped', skip_reason: reason)
  end

  def mark_cancelled!
    update!(status: 'cancelled')
  end

  def mark_sent!(message:, conversation:, rendered_body:)
    update!(
      status: 'sent',
      sent_at: Time.current,
      message_id: message.id,
      conversation_id: conversation.id,
      rendered_body: rendered_body
    )
  end

  def mark_failed!(error)
    update!(status: 'failed', failure_reason: error.to_s.first(2000))
  end
end
