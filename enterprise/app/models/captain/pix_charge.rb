# == Schema Information
#
# Table name: captain_pix_charges
#
#  id                  :bigint           not null, primary key
#  e2eid               :string
#  paid_at             :datetime
#  pix_copia_e_cola    :text
#  raw_webhook_payload :jsonb
#  status              :string
#  txid                :string
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  reservation_id      :bigint           not null
#  unit_id             :bigint           not null
#
# Indexes
#
#  idx_cp_charges_e2eid                         (e2eid)
#  idx_cp_charges_txid                          (txid) UNIQUE
#  index_captain_pix_charges_on_e2eid           (e2eid)
#  index_captain_pix_charges_on_reservation_id  (reservation_id)
#  index_captain_pix_charges_on_txid            (txid)
#  index_captain_pix_charges_on_unit_id         (unit_id)
#
# Foreign Keys
#
#  fk_rails_...  (reservation_id => captain_reservations.id)
#  fk_rails_...  (unit_id => captain_units.id)
#
class Captain::PixCharge < ApplicationRecord
  self.table_name = 'captain_pix_charges'

  EXPIRATION_SECONDS = 3600 # 1 hora

  belongs_to :reservation, class_name: 'Captain::Reservation'
  belongs_to :unit, class_name: 'Captain::Unit'

  enum status: { active: 'active', paid: 'paid', expired: 'expired', failed: 'failed' }

  validates :txid, presence: true, uniqueness: true
  validates :unit_id, presence: true

  def expires_at
    return nil unless created_at

    created_at + EXPIRATION_SECONDS.seconds
  end

  def expired_by_time?(now = Time.current)
    return false unless created_at

    now > expires_at
  end

  # Retorna o valor original da cobrança a partir do payload da Inter
  def original_value
    if raw_webhook_payload.present?
      payload = raw_webhook_payload.is_a?(String) ? JSON.parse(raw_webhook_payload) : raw_webhook_payload

      # Inter V2: { "valor": { "original": "140.00" } }
      val = payload.dig('valor', 'original')
      return val.to_f if val.present?
    end

    reservation&.total_amount
  end
end
