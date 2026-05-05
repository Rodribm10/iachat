class DeleteObjectJob < ApplicationJob
  queue_as :low

  BATCH_SIZE = 5_000
  INBOX_DEPENDENT_TABLES = %i[
    captain_feedback_logs
    captain_lifecycle_deliveries
    captain_reminders
    captain_reservations
    captain_gallery_items
    captain_inbox_automations
    captain_inbox_reminder_settings
    captain_inboxes
    captain_notification_templates
    captain_pricing_inboxes
    captain_tool_configs
    captain_unit_inboxes
    jasmine_inbox_collections
    jasmine_inbox_settings
    jasmine_tool_configs
  ].freeze
  INBOX_NULLIFY_TARGETS = [
    [:captain_conversation_insights, :inbox_id],
    [:captain_pricings, :inbox_id],
    [:jasmine_collections, :owner_inbox_id],
    [:captain_units, :inbox_id],
    [:captain_units, :concierge_inbox_id]
  ].freeze

  def perform(object, user = nil, ip = nil)
    # Pre-purge heavy associations for large objects to avoid
    # timeouts & race conditions due to destroy_async fan-out.
    purge_heavy_associations(object)
    object.destroy!
    process_post_deletion_tasks(object, user, ip)
  end

  def process_post_deletion_tasks(object, user, ip); end

  private

  def heavy_associations
    {
      Account => %i[conversations contacts inboxes reporting_events],
      Inbox => %i[conversations contact_inboxes reporting_events]
    }.freeze
  end

  def purge_heavy_associations(object)
    purge_inbox_blocking_associations(object) if object.is_a?(Inbox)

    klass = heavy_associations.keys.find { |k| object.is_a?(k) }
    return unless klass

    heavy_associations[klass].each do |assoc|
      next unless object.respond_to?(assoc)

      batch_destroy(object.public_send(assoc))
    end
  end

  def batch_destroy(relation)
    relation.find_in_batches(batch_size: BATCH_SIZE) do |batch|
      batch.each(&:destroy!)
    end
  end

  def purge_inbox_blocking_associations(inbox)
    inbox_id = inbox.id
    reservation_ids = select_ids(:captain_reservations, :inbox_id, inbox_id)

    purge_reservation_children(reservation_ids)

    # fazer.ai/Captain tables hold hard FKs to inboxes. If these survive, the
    # async delete job fails and the UI shows the inbox again on refresh.
    INBOX_DEPENDENT_TABLES.each { |table| delete_by_column(table, :inbox_id, inbox_id) }
    nullify_inbox_references(inbox_id)
  end

  def purge_reservation_children(reservation_ids)
    delete_where_in(:captain_lifecycle_deliveries, :captain_reservation_id, reservation_ids)
    delete_where_in(:captain_pix_charges, :reservation_id, reservation_ids)
  end

  def nullify_inbox_references(inbox_id)
    INBOX_NULLIFY_TARGETS.each do |table, column|
      nullify_by_column(table, column, inbox_id)
    end
  end

  def select_ids(table, column, value)
    return [] unless column_available?(table, column)

    sql = "SELECT id FROM #{quote_table(table)} WHERE #{quote_column(column)} = #{Integer(value)}"
    db.select_values(sql).map(&:to_i)
  end

  def delete_where_in(table, column, values)
    return if values.blank?
    return unless column_available?(table, column)

    db.execute("DELETE FROM #{quote_table(table)} WHERE #{quote_column(column)} IN (#{values.map { |v| Integer(v) }.join(',')})")
  end

  def delete_by_column(table, column, value)
    return unless column_available?(table, column)

    db.execute("DELETE FROM #{quote_table(table)} WHERE #{quote_column(column)} = #{Integer(value)}")
  end

  def nullify_by_column(table, column, value)
    return unless column_available?(table, column)

    db.execute("UPDATE #{quote_table(table)} SET #{quote_column(column)} = NULL WHERE #{quote_column(column)} = #{Integer(value)}")
  end

  def column_available?(table, column)
    db.data_source_exists?(table.to_s) && db.column_exists?(table.to_s, column.to_s)
  end

  def quote_table(table)
    db.quote_table_name(table)
  end

  def quote_column(column)
    db.quote_column_name(column)
  end

  def db
    ActiveRecord::Base.connection
  end
end

DeleteObjectJob.prepend_mod_with('DeleteObjectJob')
