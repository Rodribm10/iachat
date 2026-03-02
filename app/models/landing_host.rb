# == Schema Information
#
# Table name: landing_hosts
#
#  id         :bigint           not null, primary key
#  active     :boolean
#  auto_label :string
#  hostname   :string
#  unit_code  :string
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  inbox_id   :integer
#
# Indexes
#
#  index_landing_hosts_on_hostname  (hostname) UNIQUE
#
class LandingHost < ApplicationRecord
end
