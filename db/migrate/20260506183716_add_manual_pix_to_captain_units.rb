class AddManualPixToCaptainUnits < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def change
    add_column :captain_units, :pix_mode, :string, default: 'inter_dynamic', null: false
    add_column :captain_units, :manual_pix_key, :string
    add_column :captain_units, :manual_pix_key_type, :string
    add_column :captain_units, :manual_pix_owner_name, :string
    add_column :captain_units, :manual_pix_bank_name, :string

    add_index :captain_units, :pix_mode, algorithm: :concurrently

    add_column :captain_pix_charges, :provider, :string, default: 'inter', null: false
    add_column :captain_pix_charges, :manual_proof_payload, :jsonb
    add_column :captain_pix_charges, :manual_review_reason, :string

    add_index :captain_pix_charges, :provider, algorithm: :concurrently
  end
end
