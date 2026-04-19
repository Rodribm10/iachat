# == Schema Information
#
# Table name: captain_contact_memories
#
#  id                     :bigint           not null, primary key
#  account_id             :bigint           not null
#  contact_id             :bigint           not null
#  memory_type            :string           not null
#  content                :text             not null
#  evidence               :text             not null
#  confidence             :float            not null
#  scope                  :string           not null, default: 'global'
#  embedding              :vector(1536)
#  source_conversation_id :bigint
#  source_unit_id         :bigint
#  source_inbox_id        :bigint
#  expires_at             :datetime
#  last_verified_at       :datetime         not null
#  superseded_at          :datetime
#  superseded_by_id       :bigint
#  deleted_at             :datetime
#  metadata               :jsonb            not null, default: {}
#  created_at             :datetime         not null
#  updated_at             :datetime         not null
#
class Captain::ContactMemory < ApplicationRecord
  self.table_name = 'captain_contact_memories'

  MEMORY_TYPES = %w[
    preferencia data_comemorativa vinculo_social padrao_comportamental
    reclamacao feedback_positivo restricao vinculo_comercial contexto_pessoal
  ].freeze

  belongs_to :account
  belongs_to :contact
  belongs_to :source_conversation, class_name: 'Conversation', optional: true
  belongs_to :source_unit, class_name: 'Captain::Unit', optional: true
  belongs_to :source_inbox, class_name: 'Inbox', optional: true
  belongs_to :superseded_by, class_name: 'Captain::ContactMemory', optional: true

  has_neighbors :embedding, normalize: true

  validates :memory_type, presence: true, inclusion: { in: MEMORY_TYPES }
  validates :content, presence: true, length: { maximum: 1000 }
  validates :evidence, presence: true
  validates :confidence, presence: true, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 1 }
  validates :scope, presence: true

  scope :active, lambda {
    where(deleted_at: nil, superseded_at: nil)
      .where('expires_at IS NULL OR expires_at > ?', Time.current)
  }

  scope :for_contact, ->(id) { where(contact_id: id) }
  scope :by_type, ->(type) { where(memory_type: type) }

  scope :scope_compatible, lambda { |unit_id|
    if unit_id.present?
      where(scope: ['global', "unit:#{unit_id}"])
    else
      where(scope: 'global')
    end
  }

  def soft_delete!
    update!(deleted_at: Time.current)
  end

  def supersede_by!(other)
    update!(superseded_at: Time.current, superseded_by_id: other.id)
  end

  def recall_weight
    return 0.7 if expires_at.present? && expires_at < Time.current

    1.0
  end
end
