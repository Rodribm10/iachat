# == Schema Information
#
# Table name: captain_units
#
#  id                             :bigint           not null, primary key
#  inter_account_number           :string
#  inter_cert_content             :text
#  inter_cert_path                :string
#  inter_client_secret            :string
#  inter_key_content              :text
#  inter_key_path                 :string
#  inter_pix_key                  :string
#  last_synced_at                 :datetime
#  leader_whatsapp                :string
#  name                           :string           not null
#  payment_receipt_review_enabled :boolean          default(FALSE), not null
#  plug_play_token                :string
#  proactive_pix_polling_enabled  :boolean          default(FALSE), not null
#  reservation_source_tag         :string
#  reservations_sync_enabled      :boolean
#  status                         :string
#  suite_category_images          :jsonb            not null
#  visible_suite_categories       :jsonb            not null
#  webhook_configured_at          :datetime
#  webhook_url                    :string
#  created_at                     :datetime         not null
#  updated_at                     :datetime         not null
#  account_id                     :bigint           not null
#  captain_brand_id               :bigint           not null
#  inbox_id                       :bigint
#  inter_client_id                :string
#  plug_play_id                   :string
#
# Indexes
#
#  index_captain_units_on_account_id        (account_id)
#  index_captain_units_on_captain_brand_id  (captain_brand_id)
#  index_captain_units_on_inbox_id          (inbox_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (captain_brand_id => captain_brands.id)
#  fk_rails_...  (inbox_id => inboxes.id)
#

class Captain::Unit < ApplicationRecord
  belongs_to :account
  # belongs_to :captain_brand, class_name: 'Captain::Brand', optional: true

  encrypts :inter_client_secret, :inter_cert_content, :inter_key_content

  validates :name, presence: true
  validates :inter_pix_key, presence: true, on: :update
  validates :inter_account_number, presence: true, on: :update

  # Atributos resolvidos que o controller já espera ter, fallback na necessidade para arquivos (mesmo não sendo mais o padrão preferido).
  def resolved_inter_cert_path
    return nil if inter_cert_content.present?

    inter_cert_path
  end

  def resolved_inter_key_path
    return nil if inter_key_content.present?

    inter_key_path
  end
end
