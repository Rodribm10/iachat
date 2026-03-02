class AddMessageSignatureDefaultNameToInboxes < ActiveRecord::Migration[7.0]
  def change
    add_column :inboxes, :message_signature_default_name, :string
  end
end
