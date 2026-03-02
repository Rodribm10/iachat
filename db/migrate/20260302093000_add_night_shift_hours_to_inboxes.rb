class AddNightShiftHoursToInboxes < ActiveRecord::Migration[7.0]
  def change
    add_column :inboxes, :message_signature_night_shift_start, :string, default: '19:00'
    add_column :inboxes, :message_signature_night_shift_end, :string, default: '07:00'
  end
end
