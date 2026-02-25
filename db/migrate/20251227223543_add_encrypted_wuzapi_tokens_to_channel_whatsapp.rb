class AddEncryptedWuzapiTokensToChannelWhatsapp < ActiveRecord::Migration[7.1]
  def change
    add_column :channel_whatsapp, :encrypted_wuzapi_user_token, :string
    add_column :channel_whatsapp, :encrypted_wuzapi_user_token_iv, :string
    add_column :channel_whatsapp, :encrypted_wuzapi_admin_token, :string
    add_column :channel_whatsapp, :encrypted_wuzapi_admin_token_iv, :string
  end
end
