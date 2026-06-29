class Api::V1::Accounts::Sinal::AgentTokensController < ApplicationController
  before_action :authenticate_sinal_internal_token!

  def show
    account = Account.find(params[:account_id])
    account_user = AccountUser.find_by!(
      account_id: account.id,
      user_id: params[:id]
    )
    user = account_user.user
    access_token = user.access_token || AccessToken.create!(owner: user)

    render json: {
      chatwoot_user_id: user.id.to_s,
      name: user.name,
      email: user.email,
      api_access_token: access_token.token
    }
  end

  private

  def authenticate_sinal_internal_token!
    expected = ENV.fetch('SINAL_INTERNAL_TOKEN', nil)
    provided = request.headers['X-Sinal-Internal-Token'].to_s

    return head :unauthorized if expected.blank?
    return head :unauthorized if provided.blank?
    return head :unauthorized if provided.bytesize != expected.bytesize
    return if ActiveSupport::SecurityUtils.secure_compare(provided, expected)

    head :unauthorized
  end
end
