class AddConciergeToCaptainUnits < ActiveRecord::Migration[7.1]
  def change
    add_reference :captain_units, :concierge_inbox,
                  foreign_key: { to_table: :inboxes },
                  null: true
    add_column :captain_units, :concierge_config, :jsonb, null: false, default: {}
  end
end
