class AddEngineToCaptainAssistants < ActiveRecord::Migration[7.1]
  def change
    add_column :captain_assistants, :engine, :string, default: 'captain_interno', null: false
    add_column :captain_assistants, :hermes_profile_name, :string
    add_column :captain_assistants, :hermes_webhook_base_url, :string
    add_index :captain_assistants, :engine
  end
end
