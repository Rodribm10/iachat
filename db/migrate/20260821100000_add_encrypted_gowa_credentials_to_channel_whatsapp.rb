class AddEncryptedGowaCredentialsToChannelWhatsapp < ActiveRecord::Migration[7.1]
  def change
    add_column :channel_whatsapp, :gowa_username, :string
    add_column :channel_whatsapp, :gowa_username_iv, :string
    add_column :channel_whatsapp, :gowa_password, :string
    add_column :channel_whatsapp, :gowa_password_iv, :string
  end
end
