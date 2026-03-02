class AddShiftSignaturesToInboxes < ActiveRecord::Migration[7.0]
  def change
    add_column :inboxes, :message_signature_day_name, :string
    add_column :inboxes, :message_signature_night_even_name, :string
    add_column :inboxes, :message_signature_night_odd_name, :string
  end
end
