class AddCascadeToCaptainContactMemoriesForeignKeys < ActiveRecord::Migration[7.1]
  def up
    # Remove existing RESTRICT FKs
    remove_foreign_key :captain_contact_memories, :accounts
    remove_foreign_key :captain_contact_memories, :contacts

    # Re-add with ON DELETE CASCADE
    add_foreign_key :captain_contact_memories, :accounts, on_delete: :cascade
    add_foreign_key :captain_contact_memories, :contacts, on_delete: :cascade
  end

  def down
    remove_foreign_key :captain_contact_memories, :accounts
    remove_foreign_key :captain_contact_memories, :contacts

    add_foreign_key :captain_contact_memories, :accounts
    add_foreign_key :captain_contact_memories, :contacts
  end
end
