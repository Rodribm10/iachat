class AddProvisioningColumnsToCaptainAssistants < ActiveRecord::Migration[7.1]
  def change
    add_column :captain_assistants, :hermes_subscription_secret, :string
    add_column :captain_assistants, :hermes_port, :integer
    add_column :captain_assistants, :parent_assistant_id, :bigint

    add_index :captain_assistants, :parent_assistant_id
    add_index :captain_assistants,
              :hermes_port,
              unique: true,
              where: 'hermes_port IS NOT NULL',
              name: 'idx_captain_assistants_hermes_port_unique'
  end
end
