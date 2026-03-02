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
    LandingHost.find_by(hostname: params[:hostname].to_s.strip, active: true)&.inbox_id
  end

  def click_params
    {
      inbox_id: resolved_inbox_id,
      ip: params[:ip].presence || request.remote_ip,
      user_agent: request.user_agent || params[:user_agent],
      hostname: params[:hostname].to_s.strip,
      source: params[:source],
      campanha: params[:campanha],
      lp: params[:lp],
      status: :clicked
    }
  end
end
