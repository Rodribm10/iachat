class CreateCaptainNotificationTemplates < ActiveRecord::Migration[7.1]
  def change
    create_table :captain_notification_templates do |t|
      t.references :captain_unit, null: false, foreign_key: { to_table: :captain_units }
      t.string :label, null: false
      t.text :content, null: false
      t.integer :timing_minutes, null: false, default: 10
      t.integer :timing_direction, null: false, default: 0
      t.boolean :active, null: false, default: true
      t.integer :position, null: false, default: 0

      t.timestamps
    end

    add_index :captain_notification_templates, [:captain_unit_id, :active],
              name: 'idx_notif_templates_unit_active'
  end
end
