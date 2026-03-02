class ChangeNotificationTemplatesToInbox < ActiveRecord::Migration[7.1]
  def up
    remove_index :captain_notification_templates,
                 column: %i[captain_unit_id active],
                 name: 'idx_notif_templates_unit_active',
                 if_exists: true
    remove_column :captain_notification_templates, :captain_unit_id, :bigint

    add_column :captain_notification_templates, :inbox_id, :bigint
    add_foreign_key :captain_notification_templates, :inboxes, column: :inbox_id
    add_index :captain_notification_templates, %i[inbox_id active],
              name: 'idx_notif_templates_inbox_active'
  end

  def down
    remove_index :captain_notification_templates,
                 name: 'idx_notif_templates_inbox_active',
                 if_exists: true
    remove_foreign_key :captain_notification_templates, :inboxes
    remove_column :captain_notification_templates, :inbox_id, :bigint

    add_column :captain_notification_templates, :captain_unit_id, :bigint
    add_index :captain_notification_templates, %i[captain_unit_id active],
              name: 'idx_notif_templates_unit_active'
  end
end
