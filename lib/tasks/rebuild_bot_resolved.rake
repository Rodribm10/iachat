# Rebuild conversation_bot_resolved retroactively
#
# Removes 'conversation_bot_resolved' reporting events that were created with the
# old (buggy) classification rule, where outgoing messages with sender_type=NULL
# (= human replied directly via the connected WhatsApp app, not via Chatwoot UI)
# were not considered as human interaction. The bot was incorrectly credited.
#
# What this task does:
#   1. Finds all conversation_bot_resolved events whose conversations contain at
#      least one outgoing message with sender_id IS NULL (= replied externally).
#   2. (Optional) Saves the count + ids to a snapshot file before deleting.
#   3. Deletes those events. The classification will be re-evaluated correctly
#      for any *future* resolution because the listener was fixed.
#
# Idempotent: re-running on a clean dataset is a no-op.
#
# Usage:
#   # Dry-run (default) — counts only, no delete
#   bundle exec rake reports:rebuild_bot_resolved
#
#   # Actually delete
#   APPLY=true bundle exec rake reports:rebuild_bot_resolved
#
#   # Restrict to a specific account (recommended on multi-tenant prod)
#   APPLY=true ACCOUNT_ID=1 bundle exec rake reports:rebuild_bot_resolved
#
#   # Snapshot ids to a file before deleting (audit trail)
#   APPLY=true SNAPSHOT_PATH=/tmp/bot_resolved_purge.csv bundle exec rake reports:rebuild_bot_resolved

namespace :reports do
  desc 'Remove buggy conversation_bot_resolved events created before the sender-NIL fix'
  task rebuild_bot_resolved: :environment do
    apply = ENV['APPLY'].to_s.casecmp('true').zero?
    account_id = ENV['ACCOUNT_ID'].presence&.to_i
    snapshot_path = ENV['SNAPSHOT_PATH'].presence

    base_scope = ReportingEvent.where(name: 'conversation_bot_resolved')
    base_scope = base_scope.where(account_id: account_id) if account_id

    affected_conversation_ids = Message
                                .where(message_type: :outgoing, sender_id: nil)
                                .distinct
                                .pluck(:conversation_id)

    bad_events = base_scope.where(conversation_id: affected_conversation_ids)

    total_events = base_scope.count
    purge_count = bad_events.count

    puts '=== Rebuild conversation_bot_resolved ==='
    puts "Account filter: #{account_id || 'ALL'}"
    puts "Total bot_resolved events in scope: #{total_events}"
    puts "Events to purge (had outgoing with sender_id NULL): #{purge_count}"
    puts "Mode: #{apply ? 'APPLY (will delete)' : 'DRY-RUN (no changes)'}"

    if purge_count.zero?
      puts 'Nothing to do — already clean.'
      next
    end

    if snapshot_path
      File.open(snapshot_path, 'w') do |f|
        f.puts 'reporting_event_id,conversation_id,account_id,inbox_id,created_at'
        bad_events.find_each(batch_size: 500) do |re|
          f.puts [re.id, re.conversation_id, re.account_id, re.inbox_id, re.created_at.iso8601].join(',')
        end
      end
      puts "Snapshot written to #{snapshot_path}"
    end

    unless apply
      puts 'DRY-RUN finished. Re-run with APPLY=true to delete.'
      next
    end

    deleted = bad_events.delete_all
    puts "Deleted #{deleted} reporting_events. Bot resolution metrics will reflect the new count immediately."
  end
end
