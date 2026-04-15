class CreateCaptainLifecycleTables < ActiveRecord::Migration[7.1]
  def change
    create_lifecycle_rules_table
    create_lifecycle_deliveries_table
    create_lifecycle_configs_table
  end

  private

  def create_lifecycle_rules_table
    create_table :captain_lifecycle_rules do |t|
      t.references :account, null: false, foreign_key: true, index: true
      t.string :name, null: false
      t.text :description
      t.boolean :enabled, null: false, default: true
      t.string :event, null: false
      t.integer :offset_minutes, null: false, default: 0
      t.jsonb :filters, null: false, default: {}
      t.string :message_type, null: false, default: 'text'
      t.text :message_body, null: false
      t.jsonb :message_payload
      t.integer :priority, null: false, default: 50
      t.references :created_by_user, foreign_key: { to_table: :users }, index: true
      t.timestamps
    end
    add_index :captain_lifecycle_rules, %i[account_id enabled event]
  end

  def create_lifecycle_deliveries_table # rubocop:disable Metrics/MethodLength
    create_table :captain_lifecycle_deliveries do |t|
      t.references :account, null: false, foreign_key: true, index: true
      t.references :lifecycle_rule,
                   foreign_key: { to_table: :captain_lifecycle_rules },
                   index: { name: 'idx_lifecycle_deliveries_rule' }
      t.references :captain_reservation,
                   null: false,
                   foreign_key: true,
                   index: { name: 'idx_lifecycle_deliveries_reservation' }
      t.references :conversation, foreign_key: true
      t.references :message, foreign_key: true
      t.references :inbox, foreign_key: true
      t.datetime :fire_at, null: false
      t.datetime :sent_at
      t.string :status, null: false, default: 'scheduled'
      t.string :skip_reason
      t.text :failure_reason
      t.text :rendered_body
      t.string :origin, null: false, default: 'scheduled_lifecycle'
      t.timestamps
    end
    add_delivery_indexes
  end

  def add_delivery_indexes
    add_index :captain_lifecycle_deliveries,
              %i[captain_reservation_id origin status],
              name: 'idx_lifecycle_deliveries_cap_check'
    add_index :captain_lifecycle_deliveries,
              %i[account_id status fire_at],
              name: 'idx_lifecycle_deliveries_dashboard'
    add_index :captain_lifecycle_deliveries,
              :fire_at,
              where: "status = 'scheduled'",
              name: 'idx_lifecycle_deliveries_scheduled'
  end

  def create_lifecycle_configs_table
    create_table :captain_lifecycle_configs do |t|
      t.references :account, null: false, foreign_key: true, index: { unique: true }
      t.boolean :quiet_hours_enabled, null: false, default: false
      t.time :quiet_hours_from, null: false, default: '23:00'
      t.time :quiet_hours_to, null: false, default: '08:00'
      t.integer :min_interval_minutes, null: false, default: 30
      t.boolean :pause_on_customer_reply, null: false, default: false
      t.integer :pause_on_customer_reply_within_minutes, null: false, default: 60
      t.references :opt_out_label, foreign_key: { to_table: :labels }
      t.timestamps
    end
  end
end
