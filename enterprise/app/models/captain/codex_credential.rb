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
