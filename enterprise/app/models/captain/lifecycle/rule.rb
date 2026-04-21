# frozen_string_literal: true

# == Schema Information
#
# Table name: captain_lifecycle_rules
#
#  id                 :bigint           not null, primary key
#  description        :text
#  enabled            :boolean          default(TRUE), not null
#  event              :string           not null
#  filters            :jsonb            not null
#  message_body       :text             not null
#  message_payload    :jsonb
#  message_type       :string           default("text"), not null
#  name               :string           not null
#  offset_minutes     :integer          default(0), not null
#  priority           :integer          default(50), not null
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  account_id         :bigint           not null
#  created_by_user_id :bigint
#
# Indexes
#
#  idx_on_account_id_enabled_event_2d8b8a9942           (account_id,enabled,event)
#  index_captain_lifecycle_rules_on_account_id          (account_id)
#  index_captain_lifecycle_rules_on_created_by_user_id  (created_by_user_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (created_by_user_id => users.id)
#
class Captain::Lifecycle::Rule < ApplicationRecord
  self.table_name = 'captain_lifecycle_rules'

  EVENTS = %w[
    reservation.confirmed
    checkin.scheduled_at
    checkin.detected
    checkout.scheduled_at
    checkout.detected
    reservation.cancelled
    reservation.no_show
  ].freeze

  MESSAGE_TYPES = %w[text buttons list url_button].freeze

  belongs_to :account
  belongs_to :created_by_user, class_name: 'User', optional: true

  validates :name, presence: true
  validates :event, presence: true, inclusion: { in: EVENTS }
  validates :message_body, presence: true
  validates :message_type, inclusion: { in: MESSAGE_TYPES }

  scope :active, -> { where(enabled: true) }
  scope :for_event, ->(event) { where(event: event) }

  def matches_reservation?(reservation)
    return false unless reservation

    filters_hash = filters.presence || {}
    matches_unit?(filters_hash, reservation) &&
      matches_categoria?(filters_hash, reservation) &&
      matches_permanencia?(filters_hash, reservation)
  end

  private

  def matches_unit?(filters_hash, reservation)
    unit_ids = Array(filters_hash['unit_ids'])
    return true if unit_ids.empty?

    unit_ids.include?(reservation.captain_unit_id)
  end

  def matches_categoria?(filters_hash, reservation)
    categorias = Array(filters_hash['categorias'])
    return true if categorias.empty?

    categorias.include?(reservation.suite_identifier)
  end

  def matches_permanencia?(filters_hash, reservation)
    permanencias = Array(filters_hash['permanencias'])
    return true if permanencias.empty?

    actual = reservation.metadata.to_h['permanencia']
    permanencias.include?(actual)
  end
end
