# frozen_string_literal: true

class Captain::Lifecycle::Guards::OptOutLabel < Captain::Lifecycle::Guards::Base
  def check
    config = Captain::Lifecycle::Config.for_account(@account)
    label = config.opt_out_label
    return pass if label.blank?

    contact = @reservation.contact
    return pass if contact.blank?

    return skip('opt_out_label') if contact.label_list.include?(label.title)

    pass
  end
end
