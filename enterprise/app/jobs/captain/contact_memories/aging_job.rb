class Captain::ContactMemories::AgingJob < ApplicationJob
  queue_as :scheduled_jobs

  DELETE_ON_EXPIRE = %w[reclamacao feedback_positivo vinculo_social].freeze
  MAX_ACTIVE_PER_CONTACT = 50

  def perform
    soft_delete_expired_deletable
    prune_per_contact_lru
  end

  private

  def soft_delete_expired_deletable
    Captain::ContactMemory
      .where(memory_type: DELETE_ON_EXPIRE)
      .where('expires_at < ?', Time.current)
      .where(deleted_at: nil)
      .update_all(deleted_at: Time.current, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
  end

  def prune_per_contact_lru
    over_limit_contact_ids.each do |contact_id|
      excess = Captain::ContactMemory.active.for_contact(contact_id).count - MAX_ACTIVE_PER_CONTACT
      next if excess <= 0

      ids_to_delete = Captain::ContactMemory
                      .active
                      .for_contact(contact_id)
                      .order(last_verified_at: :asc)
                      .limit(excess)
                      .pluck(:id)

      Captain::ContactMemory
        .where(id: ids_to_delete)
        .update_all(deleted_at: Time.current, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
    end
  end

  def over_limit_contact_ids
    Captain::ContactMemory
      .active
      .group(:contact_id)
      .having('COUNT(*) > ?', MAX_ACTIVE_PER_CONTACT)
      .pluck(:contact_id)
  end
end
