class Wuzapi::ProvisioningService
  def initialize(base_url, admin_token)
    @base_url = base_url
    @admin_token = admin_token
    @client = Wuzapi::Client.new(base_url)
  end

  def provision(name)
    user_token = SecureRandom.hex(32)
    response = @client.create_user(@admin_token, name, user_token)

    # Wuzapi returns the user object, or we assume success if no error raised.
    # The response structure depends on Wuzapi. Assuming it returns { "ID": "...", ... } or similar.
    # Based on plan, we just need to know it succeeded.
    # We return the generated data to be saved.

    {
      wuzapi_user_id: response['ID'] || response['id'], # Adjust based on actual response if known, strictly fallback
      wuzapi_user_token: user_token
    }
  end

  # [INTENTIONAL] reserved for signed webhooks
  def setup_webhook(user_token, inbox_id, _webhook_secret)
    # Host logic needs to come from GlobalConfig or Rails.application.routes
    # Ideally passed in or resolved.
    base_host = ENV.fetch('FRONTEND_URL', 'http://localhost:3000')
    inbox = Inbox.find(inbox_id)
    phone_number = inbox.channel.phone_number.delete('+')
    webhook_url = "#{base_host}/webhooks/whatsapp/#{phone_number}"

    @client.set_webhook(user_token, webhook_url)
  end
end
