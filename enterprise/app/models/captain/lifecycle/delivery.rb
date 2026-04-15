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
