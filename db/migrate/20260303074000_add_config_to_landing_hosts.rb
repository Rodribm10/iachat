class AddConfigToLandingHosts < ActiveRecord::Migration[7.0]
  def change
    add_column :landing_hosts, :initial_message, :text
    add_column :landing_hosts, :default_source, :string
    add_column :landing_hosts, :default_campanha, :string
    add_column :landing_hosts, :custom_config, :jsonb, default: {}
  end
end
