# == Schema Information
#
# Table name: captain_reservations
#
#  id                    :bigint           not null, primary key
#  check_in_at           :datetime         not null
#  check_out_at          :datetime         not null
#  created_by_type       :string
#  metadata              :jsonb            not null
#  payment_status        :string           default("pending")
#  status                :integer          default("scheduled"), not null
#  suite_identifier      :string
#  total_amount          :decimal(10, 2)
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#  account_id            :bigint           not null
#  captain_brand_id      :bigint
#  captain_unit_id       :bigint
#  contact_id            :bigint           not null
#  contact_inbox_id      :bigint           not null
#  conversation_id       :bigint
#  created_by_id         :bigint
#  current_pix_charge_id :bigint
#  inbox_id              :bigint           not null
#  integracao_id         :string
#
# Indexes
#
#  idx_reservations_account_payment_status                  (account_id,payment_status)
#  idx_reservations_account_status                          (account_id,status)
#  idx_reservations_board_unit_checkin_status               (captain_unit_id,check_in_at,status)
#  idx_reservations_board_unit_checkout_status              (captain_unit_id,check_out_at,status)
#  index_captain_reservations_on_account_id                 (account_id)
#  index_captain_reservations_on_account_id_and_inbox_id    (account_id,inbox_id)
#  index_captain_reservations_on_captain_brand_id           (captain_brand_id)
#  index_captain_reservations_on_captain_unit_id            (captain_unit_id)
#  index_captain_reservations_on_contact_id                 (contact_id)
#  index_captain_reservations_on_contact_id_and_inbox_id    (contact_id,inbox_id)
#  index_captain_reservations_on_contact_inbox_id           (contact_inbox_id)
#  index_captain_reservations_on_conversation_id            (conversation_id)
#  index_captain_reservations_on_inbox_id                   (inbox_id)
#  index_captain_reservations_on_integracao_id              (integracao_id)
#  index_captain_reservations_on_integracao_id_and_unit_id  (integracao_id,captain_unit_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (captain_brand_id => captain_brands.id)
#  fk_rails_...  (captain_unit_id => captain_units.id)
#  fk_rails_...  (contact_id => contacts.id)
#  fk_rails_...  (contact_inbox_id => contact_inboxes.id)
#  fk_rails_...  (conversation_id => conversations.id)
#  fk_rails_...  (inbox_id => inboxes.id)
#
class Captain::Reservation < ApplicationRecord
  self.table_name = 'captain_reservations'

  belongs_to :account
  belongs_to :inbox
  belongs_to :contact
  belongs_to :contact_inbox
  belongs_to :conversation, class_name: '::Conversation', optional: true
  belongs_to :brand, class_name: 'Captain::Brand', foreign_key: 'captain_brand_id', optional: true
  belongs_to :unit, class_name: 'Captain::Unit', foreign_key: 'captain_unit_id', optional: true
  belongs_to :current_pix_charge, class_name: 'Captain::PixCharge', optional: true

  enum status: { scheduled: 0, active: 1, completed: 2, cancelled: 3, pending_payment: 4, draft: 5 }

  validates :suite_identifier, presence: true
  validates :check_in_at, presence: true
  validates :check_out_at, presence: true
  validate :check_out_after_check_in

  scope :filter_by_status, ->(status) { where(status: status) if status.present? && status != 'all' }
  scope :filter_by_date_range, lambda { |from, to|
    if from.present? && to.present?
      where(check_in_at: from..to)
    elsif from.present?
      where('check_in_at >= ?', from)
    elsif to.present?
      where('check_in_at <= ?', to)
    end
  }

  scope :in_house, -> { where(status: 'active') }

  delegate :name, :email, :phone_number, to: :contact, prefix: true

  before_validation :set_captain_unit_id, on: :create
  after_commit :sync_conversation_marker_snapshot

  def ui_status
    Captain::Reservations::MarkerBuilder.ui_status(status)
  end

  def ui_status_label
    Captain::Reservations::MarkerBuilder.status_label(ui_status)
  end

  private

  def set_captain_unit_id
    return if captain_unit_id.present?

    # Primeiro tenta a associação via CaptainInbox (fluxo principal do Captain).
    captain_inbox = CaptainInbox.find_by(inbox_id: inbox_id)
    if captain_inbox&.captain_unit_id.present?
      self.captain_unit_id = captain_inbox.captain_unit_id
      return
    end

    # Fallback: usa vínculo direto da Unidade Pix com o inbox.
    linked_unit = Captain::Unit.find_by(account_id: account_id, inbox_id: inbox_id)
    self.captain_unit_id = linked_unit&.id
  end

  def check_out_after_check_in
    return unless check_in_at.present? && check_out_at.present?

    errors.add(:check_out_at, 'deve ser posterior ao check-in') if check_out_at <= check_in_at
  end

  def sync_conversation_marker_snapshot
    Captain::Reservations::ConversationMarkerSyncService.new(reservation: self).perform
  rescue StandardError => e
    Rails.logger.error("[Captain::Reservation] failed to sync conversation marker: #{e.class} - #{e.message}")
  end
end
