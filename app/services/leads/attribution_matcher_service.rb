class Leads::AttributionMatcherService
  def initialize(conversation, inbound_ip = nil)
    @conversation = conversation
    @contact = conversation.contact
    @inbox_id = conversation.inbox_id
    @inbound_ip = inbound_ip
  end

  def perform
    return unless valid_for_matching?

    click = find_matching_click
    return unless click

    apply_attribution(click)
  end

  private

  def valid_for_matching?
    @conversation.present? && @contact.present? &&
      @conversation.custom_attributes['link_de_origem'].blank?
  end

  def find_matching_click
    base_query = LeadClick
                 .where(status: :clicked, inbox_id: @inbox_id)
                 .where('created_at > ?', 10.minutes.ago)

    return base_query.where(ip: @inbound_ip).order(created_at: :desc).first if @inbound_ip.present?

    base_query.order(created_at: :desc).first
  end

  def attribution_attrs(click)
    {
      'link_de_origem' => click.source,
      'campanha' => click.campanha,
      'lp_hostname' => click.hostname,
      'click_id' => click.id.to_s
    }
  end

  def apply_attribution(click)
    ActiveRecord::Base.transaction do
      click.update!(status: :converted, conversation_id: @conversation.id, contact_id: @contact.id)
      update_contact(click)
      update_conversation(click)
      apply_labels(click)
    end
  end

  def update_contact(click)
    @contact.update!(custom_attributes: @contact.custom_attributes.to_h.merge(attribution_attrs(click)))
  end

  def update_conversation(click)
    @conversation.update!(
      custom_attributes: @conversation.custom_attributes.to_h.merge(attribution_attrs(click))
    )
  end

  def apply_labels(click)
    @conversation.add_labels(['lead_meta']) if click.source.to_s.downcase.include?('meta')
  end
end
