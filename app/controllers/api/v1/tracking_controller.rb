class Api::V1::TrackingController < ActionController::API
  def click
    LeadClick.create!(click_params)
    head :no_content
  rescue StandardError => e
    Rails.logger.error("Error processing tracking click: #{e.message}")
    head :no_content
  end

  private

  def resolved_inbox_id
    host = params[:hostname].to_s.strip.sub(%r{^https?://}, '')
    LandingHost.find_by(hostname: host, active: true)&.inbox_id
  end

  def click_params
    base_params = {
      inbox_id: resolved_inbox_id,
      ip: params[:ip].presence || request.remote_ip,
      user_agent: request.user_agent || params[:user_agent],
      hostname: params[:hostname].to_s.strip,
      source: params[:source],
      campanha: params[:campanha],
      lp: params[:lp],
      click_id: params[:click_id],
      status: :clicked
    }

    # Se 'lp' for fornecido, extraímos os UTMs se fonte ou campanha estiverem vazios
    if base_params[:lp].present?
      begin
        uri = URI.parse(base_params[:lp])
        query = Rack::Utils.parse_nested_query(uri.query)
        base_params[:source] ||= query['utm_source']
        base_params[:campanha] ||= query['utm_campaign']
      rescue StandardError => e
        Rails.logger.warn("Error parsing LP URL for UTMs: #{e.message}")
      end
    end

    base_params
  end
end
