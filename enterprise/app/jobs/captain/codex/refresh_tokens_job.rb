class Captain::Codex::RefreshTokensJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    Captain::CodexCredential.active.expiring_soon(5.minutes).find_each do |cred|
      Captain::Codex::AuthService.refresh!(cred)
      Rails.logger.info("[Captain::Codex] Refreshed credential #{cred.id} (expires #{cred.expires_at})")
    rescue Captain::Codex::AuthService::AuthError => e
      Rails.logger.error("[Captain::Codex] Refresh failed for credential #{cred.id}: #{e.message}")
    end
  end
end
