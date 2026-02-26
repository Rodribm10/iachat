# Inherits from ActionController::Base to skip all middleware,
# authentication, and callbacks. Used for health checks
class HealthController < ActionController::Base # rubocop:disable Rails/ApplicationController
  def show
    render json: {
      version: Chatwoot.config[:version] || 'dev',
      timestamp: Time.current.to_fs(:db),
      queue_services: redis_status,
      data_services: postgres_status
    }
  end

  private

  def redis_status
    r = Redis.new(Redis::Config.app)
    r.ping ? 'ok' : 'failing'
  rescue StandardError
    'failing'
  end

  def postgres_status
    ActiveRecord::Base.connection.active? ? 'ok' : 'failing'
  rescue StandardError
    'failing'
  end
end
