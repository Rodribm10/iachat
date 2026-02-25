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
  self.table_name = 'captain_units'

  belongs_to :account
  belongs_to :brand, class_name: 'Captain::Brand', foreign_key: 'captain_brand_id', inverse_of: :units
  belongs_to :inbox, optional: true
  has_many :pix_charges, class_name: 'Captain::PixCharge', dependent: :restrict_with_error
  has_many :gallery_items, class_name: 'Captain::GalleryItem', foreign_key: :captain_unit_id, inverse_of: :captain_unit,
                           dependent: :destroy

  encrypts :inter_client_secret
  encrypts :inter_account_number
  encrypts :inter_cert_content
  encrypts :inter_key_content

  enum status: { active: 'active', inactive: 'inactive' }, _default: 'active'

  validates :name, presence: true
  validate :proactive_pix_polling_requires_inter_credentials

  def inter_credentials_present?
    inter_client_id.present? &&
      inter_client_secret.present? &&
      inter_pix_key.present? &&
      (inter_cert_content.present? || resolved_inter_cert_path.present?) &&
      (inter_key_content.present? || resolved_inter_key_path.present?)
  end

  def resolved_inter_cert_path
    resolve_certificate_path(inter_cert_path)
  end

  def resolved_inter_key_path
    resolve_certificate_path(inter_key_path)
  end

  private

  def proactive_pix_polling_requires_inter_credentials
    return unless proactive_pix_polling_enabled?
    return if inter_credentials_present?

    errors.add(
      :proactive_pix_polling_enabled,
      'só pode ser habilitado quando a integração Inter estiver completa (client id/secret, chave pix, cert e key)'
    )
  end

  # Resolve o path do certificado — suporta caminho absoluto, relativo ao Rails.root
  # ou nome de arquivo simples dentro de storage/certs/.
  def resolve_certificate_path(path)
    return nil if path.blank?
    return path if File.exist?(path)

    rails_root_path = Rails.root.join(path).to_s
    return rails_root_path if File.exist?(rails_root_path)

    filename = File.basename(path)
    fallback_path = Rails.root.join('storage/certs', filename).to_s
    return fallback_path if File.exist?(fallback_path)

    path # Retorna original se nenhum caminho for encontrado
  end
end
