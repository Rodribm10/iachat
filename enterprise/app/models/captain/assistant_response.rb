# == Schema Information
#
# Table name: captain_assistant_responses
#
#  id                :bigint           not null, primary key
#  answer            :text             not null
#  documentable_type :string
#  embedding         :vector(1536)
#  judge_verdict     :jsonb
#  promoted_at       :datetime
#  question          :string           not null
#  retired_at        :datetime
#  retired_reason    :string
#  source            :string
#  status            :integer          default("approved"), not null
#  triage_reason     :string
#  trial_until       :datetime
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  account_id        :bigint           not null
#  assistant_id      :bigint           not null
#  documentable_id   :bigint
#
# Indexes
#
#  idx_cap_asst_resp_on_documentable                  (documentable_id,documentable_type)
#  idx_cap_asst_resp_on_source                        (source)
#  idx_cap_asst_resp_on_trial_until                   (trial_until) WHERE (trial_until IS NOT NULL)
#  index_captain_assistant_responses_on_account_id    (account_id)
#  index_captain_assistant_responses_on_assistant_id  (assistant_id)
#  index_captain_assistant_responses_on_status        (status)
#  vector_idx_knowledge_entries_embedding             (embedding) USING ivfflat
#
class Captain::AssistantResponse < ApplicationRecord
  self.table_name = 'captain_assistant_responses'

  belongs_to :assistant, class_name: 'Captain::Assistant'
  belongs_to :account
  belongs_to :documentable, polymorphic: true, optional: true
  has_neighbors :embedding, normalize: true

  validates :question, presence: true, length: { maximum: 255 }
  validates :answer, presence: true

  before_validation :ensure_account
  before_validation :ensure_status
  after_commit :update_response_embedding, on: %i[create update]

  scope :ordered, -> { order(created_at: :desc) }
  scope :by_account, ->(account_id) { where(account_id: account_id) }
  scope :by_assistant, ->(assistant_id) { where(assistant_id: assistant_id) }
  scope :with_document, ->(document_id) { where(document_id: document_id) }

  # Conhecimento vivo: o que as atendentes podem recuperar numa busca.
  # `trial` está em quarentena mas responde ao cliente; `pending` aguarda
  # decisão e `retired` foi aposentado — nenhum dos dois pode ser recuperado.
  scope :retrievable, -> { where(status: %i[approved trial]) }
  scope :trial_expired, -> { trial.where(trial_until: ..Time.current) }

  enum status: { pending: 0, approved: 1, trial: 2, retired: 3 }

  SOURCES = %w[human_validated document manual].freeze
  TRIAL_PERIOD = 30.days

  validates :source, inclusion: { in: SOURCES }, allow_nil: true

  def self.search(query, account_id: nil)
    embedding = Captain::Llm::EmbeddingService.new(account_id: account_id).get_embedding(query)
    nearest_neighbors(:embedding, embedding, distance: 'cosine').limit(5)
  end

  # Fim da quarentena: o conhecimento passa a valer por tempo indeterminado.
  def promote!
    update!(status: :approved, trial_until: nil, promoted_at: Time.current)
  end

  # Aposentadoria nunca deleta — o registro fica para auditoria e reversão.
  def retire!(reason)
    update!(status: :retired, retired_at: Time.current, retired_reason: reason, trial_until: nil)
  end

  private

  def ensure_status
    self.status ||= :approved
  end

  def ensure_account
    self.account = assistant&.account
  end

  def update_response_embedding
    return unless saved_change_to_question? || saved_change_to_answer? || embedding.nil?

    Captain::Llm::UpdateEmbeddingJob.perform_later(self, "#{question}: #{answer}")
  end
end
