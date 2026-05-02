class AddCaptainUnitIdToCaptainAssistants < ActiveRecord::Migration[7.1]
  def change
    add_reference :captain_assistants,
                  :captain_unit,
                  foreign_key: { to_table: :captain_units, on_delete: :nullify },
                  null: true,
                  index: true
  end
end
