# frozen_string_literal: true

# == Schema Information
#
# Table name: captain_lifecycle_configs
#
#  id                                     :bigint           not null, primary key
#  min_interval_minutes                   :integer          default(30), not null
#  pause_on_customer_reply                :boolean          default(FALSE), not null
#  pause_on_customer_reply_within_minutes :integer          default(60), not null
#  quiet_hours_enabled                    :boolean          default(FALSE), not null
#  quiet_hours_from                       :time             default(Sat, 01 Jan 2000 23:00:00.000000000 UTC +00:00), not null
#  quiet_hours_to                         :time             default(Sat, 01 Jan 2000 08:00:00.000000000 UTC +00:00), not null
#  created_at                             :datetime         not null
#  updated_at                             :datetime         not null
#  account_id                             :bigint           not null
#  opt_out_label_id                       :bigint
#
# Indexes
#
#  index_captain_lifecycle_configs_on_account_id        (account_id) UNIQUE
#  index_captain_lifecycle_configs_on_opt_out_label_id  (opt_out_label_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (opt_out_label_id => labels.id)
#
class Captain::Lifecycle::Config < ApplicationRecord
  self.table_name = 'captain_lifecycle_configs'

  belongs_to :account
  belongs_to :opt_out_label, class_name: 'Label', optional: true

  validates :account_id, uniqueness: true
  validates :min_interval_minutes, numericality: { greater_than_or_equal_to: 0 }
  validates :pause_on_customer_reply_within_minutes, numericality: { greater_than_or_equal_to: 0 }

  def self.for_account(account)
    find_or_create_by!(account_id: account.id)
  end
end
