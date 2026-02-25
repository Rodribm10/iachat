class AddCertContentToCaptainUnits < ActiveRecord::Migration[7.1]
  def change
    add_column :captain_units, :inter_cert_content, :text
    add_column :captain_units, :inter_key_content, :text
  end
end
