# == Schema Information
#
# Table name: captain_codex_credentials
#
#  id                 :bigint           not null, primary key
#  access_token       :text             not null
#  chatgpt_plan_type  :string
#  email              :string
#  expires_at         :datetime         not null
#  last_refresh_at    :datetime
#  refresh_token      :text             not null
#  status             :string           default("active"), not null
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  chatgpt_account_id :string
#
# Indexes
#
#  index_captain_codex_credentials_on_expires_at  (expires_at)
#  index_captain_codex_credentials_on_status      (status)
#
class Captain::CodexCredential < ApplicationRecord
  self.table_name = 'captain_codex_credentials'

  STATUSES = %w[active expired revoked].freeze

  encrypts :access_token
  encrypts :refresh_token

  validates :access_token, presence: true
  validates :refresh_token, presence: true
  validates :expires_at, presence: true
  validates :status, inclusion: { in: STATUSES }

  scope :active, -> { where(status: 'active') }
  scope :expiring_soon, ->(skew = 5.minutes) { where(expires_at: ..(Time.current + skew)) }

  def self.current
    active.order(updated_at: :desc).first
  end

  def needs_refresh?(skew_seconds: 120)
    expires_at.nil? || expires_at <= Time.current + skew_seconds.seconds
  end

  def expired?
    expires_at <= Time.current
  end

  def revoke!
    update!(status: 'revoked')
  end
end
