class AddWebhookConfiguredAtToCaptainUnits < ActiveRecord::Migration[7.1]
  def change
    add_column :captain_units, :webhook_configured_at, :datetime
  end
end
