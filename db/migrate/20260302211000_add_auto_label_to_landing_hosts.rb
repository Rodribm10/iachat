class AddAutoLabelToLandingHosts < ActiveRecord::Migration[7.0]
  def change
    add_column :landing_hosts, :auto_label, :string
  end
end
