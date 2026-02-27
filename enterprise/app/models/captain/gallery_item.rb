# == Schema Information
#
# Table name: captain_gallery_items
#
#  id              :bigint           not null, primary key
#  active          :boolean          default(TRUE), not null
#  description     :text             not null
#  scope           :string           default("inbox"), not null
#  suite_category  :string           not null
#  suite_number    :string           not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  account_id      :bigint           not null
#  captain_unit_id :bigint
#  created_by_id   :bigint
#  inbox_id        :bigint
#
# Indexes
#
#  index_captain_gallery_items_on_account_and_category      (account_id,suite_category)
#  index_captain_gallery_items_on_account_and_inbox         (account_id,inbox_id)
#  index_captain_gallery_items_on_account_and_suite_number  (account_id,suite_number)
#  index_captain_gallery_items_on_account_and_unit          (account_id,captain_unit_id)
#  index_captain_gallery_items_on_account_id                (account_id)
#  index_captain_gallery_items_on_account_scope_and_inbox   (account_id,scope,inbox_id)
#  index_captain_gallery_items_on_captain_unit_id           (captain_unit_id)
#  index_captain_gallery_items_on_created_by_id             (created_by_id)
#  index_captain_gallery_items_on_inbox_id                  (inbox_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (captain_unit_id => captain_units.id)
#  fk_rails_...  (created_by_id => users.id)
#  fk_rails_...  (inbox_id => inboxes.id)
#
class Captain::GalleryItem < ApplicationRecord
  self.table_name = 'captain_gallery_items'

  belongs_to :account
  belongs_to :captain_unit, class_name: 'Captain::Unit', inverse_of: :gallery_items, optional: true
  belongs_to :inbox, optional: true
  belongs_to :created_by, class_name: 'User', optional: true

  has_one_attached :image

  enum :scope, { inbox: 'inbox', global: 'global' }, prefix: true

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(created_at: :desc) }

  before_validation :infer_inbox_from_unit
  before_validation :normalize_scope
  before_validation :clear_inbox_for_global_scope

  validates :description, :suite_category, :suite_number, presence: true
  validates :scope, inclusion: { in: scopes.keys }
  validates :suite_category, length: { maximum: 120 }
  validates :suite_number, length: { maximum: 60 }
  validate :inbox_presence_for_inbox_scope
  validate :inbox_belongs_to_account
  validate :captain_unit_belongs_to_account
  validate :image_presence
  validate :image_is_supported

  private

  def infer_inbox_from_unit
    return if inbox_id.present? || captain_unit.blank?

    self.inbox_id = captain_unit.inboxes.first&.id
  end

  def normalize_scope
    return if scope.present?

    self.scope = inbox_id.present? ? 'inbox' : 'global'
  end

  def clear_inbox_for_global_scope
    self.inbox_id = nil if scope_global?
  end

  def inbox_presence_for_inbox_scope
    return unless scope_inbox? && inbox_id.blank?

    errors.add(:inbox, 'é obrigatória para escopo de caixa de entrada')
  end

  def inbox_belongs_to_account
    return if inbox_id.blank? || inbox.blank?
    return if inbox.account_id == account_id

    errors.add(:inbox_id, 'não pertence à conta atual')
  end

  def captain_unit_belongs_to_account
    return if captain_unit_id.blank? || captain_unit.blank?
    return if captain_unit.account_id == account_id

    errors.add(:captain_unit_id, 'não pertence à conta atual')
  end

  def image_presence
    errors.add(:image, 'é obrigatória') unless image.attached?
  end

  def image_is_supported
    return unless image.attached?
    return if image.content_type.to_s.start_with?('image/')

    errors.add(:image, 'deve ser uma imagem válida (png, jpg, jpeg, webp)')
  end
end
