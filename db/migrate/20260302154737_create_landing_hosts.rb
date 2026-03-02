class CreateLandingHosts < ActiveRecord::Migration[7.1]
  def change
    create_table :landing_hosts do |t|
      t.string :hostname
      t.string :unit_code
      t.integer :inbox_id
      t.boolean :active, default: true, null: false

      t.timestamps
    end

    add_index :landing_hosts, :hostname, unique: true
  end
end
