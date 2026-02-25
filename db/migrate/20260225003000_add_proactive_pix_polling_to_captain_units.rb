class AddProactivePixPollingToCaptainUnits < ActiveRecord::Migration[7.1]
  def change
    add_column :captain_units, :proactive_pix_polling_enabled, :boolean, default: false, null: false
  end
end
