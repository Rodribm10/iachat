# rubocop:disable Layout/LineLength
# == Schema Information
#
# Table name: channel_whatsapp
#
#  id                             :bigint           not null, primary key
#  evolution_api_token            :string
#  evolution_api_token_iv         :string
#  gowa_password                  :string
#  gowa_password_iv               :string
#  gowa_username                  :string
#  gowa_username_iv               :string
#  message_templates              :jsonb
#  message_templates_last_updated :datetime
#  phone_number                   :string           not null
#  provider                       :string           default("default")
#  provider_config                :jsonb
#  provider_connection            :jsonb
#  wuzapi_admin_token             :string
#  wuzapi_admin_token_iv          :string
#  wuzapi_user_token              :string
#  wuzapi_user_token_iv           :string
#  created_at                     :datetime         not null
#  updated_at                     :datetime         not null
#  account_id                     :integer          not null
#
# Indexes
#
#  index_channel_whatsapp_on_phone_number      (phone_number) UNIQUE
#  index_channel_whatsapp_provider_connection  (provider_connection) WHERE ((provider)::text = ANY ((ARRAY['baileys'::character varying, 'zapi'::character varying])::text[])) USING gin
#
# rubocop:enable Layout/LineLength

class Channel::Whatsapp < ApplicationRecord # rubocop:disable Metrics/ClassLength
  include Channelable
  include Reauthorizable

  self.table_name = 'channel_whatsapp'
  attr_accessor :inbox_name_for_provisioning

  EDITABLE_ATTRS = [:phone_number, :provider, :wuzapi_user_token, :wuzapi_admin_token, :evolution_api_token, :gowa_username, :gowa_password,
                    :inbox_name_for_provisioning,
                    { provider_config: {} }].freeze

  # default at the moment is 360dialog lets change later.
  PROVIDERS = %w[default whatsapp_cloud wuzapi baileys zapi evolution gowa].freeze

  # Reacao so entra aqui quando o provider service sabe enviar de fato.
  # evolution e gowa ficam de fora: nenhum dos dois implementa envio de reacao.
  REACTION_SUPPORTED_PROVIDERS = %w[whatsapp_cloud baileys zapi wuzapi].freeze

  # UI-relevant subset of the baileys new-chat message cap payload that we persist in
  # provider_connection. server_sent_timestamp is intentionally dropped (it changes on every
  # snapshot, so keeping it would make the 5-min poll re-broadcast every cycle for no reason).
  NEW_CHAT_CAP_KEYS = %w[capping_status ote_status mv_status total_quota used_quota cycle_start_timestamp cycle_end_timestamp].freeze

  encrypts :wuzapi_user_token, :wuzapi_admin_token, :evolution_api_token, :gowa_username, :gowa_password

  before_validation :ensure_webhook_verify_token
  before_validation :move_tokens_to_encrypted_attributes
  before_validation :provision_wuzapi_user, on: :create
  before_validation :provision_evolution_instance, on: :create
  before_validation :provision_gowa_device, on: :create

  validates :provider, inclusion: { in: PROVIDERS }
  validates :phone_number, presence: true, uniqueness: true
  validate :validate_provider_config

  after_create :sync_templates
  # Os dois callbacks precisam de nomes de metodo diferentes: o Rails deduplica
  # callbacks de commit pelo simbolo, entao declarar :setup_webhooks nos dois
  # fazia o de create sumir em silencio (era o caso ate o sync 4.13).
  after_create_commit :setup_webhooks_on_create
  after_update_commit :setup_webhooks, if: :webhook_configuration_changed?
  before_destroy :teardown_webhooks

  def name
    'Whatsapp'
  end

  def supports_reactions?
    REACTION_SUPPORTED_PROVIDERS.include?(provider)
  end

  # Mirrors Channel::TwilioSms#voice_enabled? so the call subsystem can duck-type across providers.
  # Meta's Calling API is available to any whatsapp_cloud inbox (embedded-signup or manual keys);
  # only 360dialog (default provider) can't reach the call APIs.
  def voice_enabled?
    voice_calling_supported? &&
      provider_config['calling_enabled'].present? &&
      account.feature_enabled?('channel_voice')
  end

  # Mutes only the incoming side of calling; default on, so only an explicit false disables inbound.
  def inbound_calls_enabled?
    provider_config['inbound_calls_enabled'] != false
  end

  # Whether this inbox can do WhatsApp calling at all. Meta's Calling API is
  # reachable by any whatsapp_cloud inbox, so 360dialog inboxes can't be toggled
  # on even though calling_enabled would persist.
  def voice_calling_supported?
    provider == 'whatsapp_cloud'
  end

  def provider_service
    case provider
    when 'whatsapp_cloud'
      Whatsapp::Providers::WhatsappCloudService.new(whatsapp_channel: self)
    when 'wuzapi'
      Whatsapp::Providers::WuzapiService.new(whatsapp_channel: self)
    when 'baileys'
      Whatsapp::Providers::WhatsappBaileysService.new(whatsapp_channel: self)
    when 'zapi'
      Whatsapp::Providers::WhatsappZapiService.new(whatsapp_channel: self)
    when 'evolution'
      Whatsapp::Providers::EvolutionService.new(whatsapp_channel: self)
    when 'gowa'
      Whatsapp::Providers::GowaService.new(whatsapp_channel: self)
    else
      Whatsapp::Providers::Whatsapp360DialogService.new(whatsapp_channel: self)
    end
  end

  def use_internal_host?
    provider == 'baileys' && ENV.fetch('BAILEYS_PROVIDER_USE_INTERNAL_HOST_URL', false)
  end

  # Enables voice: turns calling on at Meta (idempotent), then re-registers webhooks
  # with the in-memory calling_enabled flag so the `calls` field is subscribed. The
  # flag is persisted only after registration succeeds, so a webhook failure can't
  # leave the inbox reporting voice_enabled? while the WABA isn't subscribed to calls.
  # Saved with validate: false to skip validate_provider_config's remote credential
  # re-check, which could spuriously fail and desync the flag from Meta.
  def enable_voice_calling!
    raise 'WhatsApp calling requires a whatsapp_cloud inbox' unless voice_calling_supported?
    raise 'WhatsApp calling requires the channel_voice feature' unless account.feature_enabled?('channel_voice')

    provider_service.update_calling_status('ENABLED')
    self.provider_config = provider_config.merge('calling_enabled' => true)
    webhook_setup_service.register_callback
    save!(validate: false)
  end

  # Disables voice: unsets calling_enabled (gates the call subsystem) and re-registers
  # webhooks, which drops `calls` from the subscription (best-effort, so a Meta outage
  # can't trap admins). Leaves Meta's WABA calling.status untouched.
  def disable_voice_calling!
    raise 'WhatsApp calling requires a whatsapp_cloud inbox' unless voice_calling_supported?

    self.provider_config = provider_config.merge('calling_enabled' => false)
    save!(validate: false)
    begin
      webhook_setup_service.register_callback
    rescue StandardError => e
      Rails.logger.warn "[WHATSAPP CALL] disable webhook re-subscribe failed: #{e.message}"
    end
  end

  def mark_message_templates_updated
    # rubocop:disable Rails/SkipsModelValidations
    update_column(:message_templates_last_updated, Time.zone.now)
    # rubocop:enable Rails/SkipsModelValidations
  end

  def update_provider_connection!(provider_connection)
    provider_connection ||= {} # deep_stringify_keys below requires a hash
    # Normalize to string keys to match the persisted jsonb (which always reads back as
    # strings) so an unchanged status is recognized as a no-op and skipped.
    normalized = provider_connection.deep_stringify_keys
    return if normalized == self.provider_connection

    assign_attributes(provider_connection: normalized)
    # NOTE: Skip `validate_provider_config?` check.
    # `Inbox.no_touching` suppresses the `has_one :inbox, touch: true` callback
    # (inherited from Channelable) so this high-frequency connection-status change does
    # NOT touch the inbox and invalidate the whole account inbox cache. The change is
    # pushed to clients via a targeted `inbox.provider_connection_updated` event.
    Inbox.no_touching { save!(validate: false) }
    broadcast_provider_connection_updated
  end

  # Proactive (REST poll) / push update of just the reach-out lock. Unlike the connection.update
  # path this carries no lease epoch, so it merges into the existing provider_connection without
  # touching connection/epoch/qr/error and reuses update_provider_connection!'s no-op guard and
  # broadcast. The with_lock reloads under SELECT FOR UPDATE so a concurrent connection.update
  # can't be lost by merging onto a stale snapshot. Callers pass nil (404/fetch error) to skip.
  def update_reachout_time_lock!(reachout_time_lock)
    return if reachout_time_lock.nil?

    with_lock do
      update_provider_connection!(provider_connection.merge('reachout_time_lock' => reachout_time_lock.deep_stringify_keys))
    end
  end

  # Same contract as update_reachout_time_lock! for the new-chat message cap (quota). We persist
  # only the UI-relevant keys (dropping the volatile server_sent_timestamp) so the poll doesn't
  # re-broadcast every cycle when nothing meaningful changed.
  def update_new_chat_cap!(new_chat_cap)
    return if new_chat_cap.nil?

    normalized = new_chat_cap.to_h.deep_stringify_keys.slice(*NEW_CHAT_CAP_KEYS)
    with_lock do
      update_provider_connection!(provider_connection.merge('new_chat_cap' => normalized))
    end
  end

  def provider_connection_data
    data = { connection: provider_connection['connection'] }
    data[:reachout_time_lock] = provider_connection['reachout_time_lock'] if provider_connection['reachout_time_lock'].present?
    data[:new_chat_cap] = provider_connection['new_chat_cap'] if provider_connection['new_chat_cap'].present?
    if Current.account_user&.administrator?
      data[:qr_data_url] = provider_connection['qr_data_url']
      data[:error] = provider_connection['error']
    end
    data
  end

  def toggle_typing_status(typing_status, conversation:)
    return unless provider_service.respond_to?(:toggle_typing_status)

    identifier = conversation.contact.identifier
    phone_number = conversation.contact.phone_number
    recipient_id = identifier || phone_number

    # Debug Log
    Rails.logger.info "[Typing] recipient_id=#{recipient_id.inspect} identifier=#{identifier.inspect} phone=#{phone_number.inspect}"

    # Validation: Ensure recipient_id is E164 compliant (digits only, maybe +).
    # If identifier is something like x@lid, we should fallback to phone_number.
    # Using suggested regex: \A\+?\d{10,15}\z
    unless recipient_id.to_s.gsub(/[\+\s\-\(\)]/, '').match?(/\A\d{10,15}\z/)
      Rails.logger.warn "[Typing] Invalid recipient_id format (#{recipient_id}). Falling back to phone_number: #{phone_number}"
      recipient_id = phone_number
    end

    provider_service.toggle_typing_status(typing_status, last_message: nil, recipient_id: recipient_id)
  end

  def update_presence(status)
    return unless provider_service.respond_to?(:update_presence)

    provider_service.update_presence(status)
  end

  def read_messages(messages, conversation:)
    return unless provider_service.respond_to?(:read_messages)
    # NOTE: This is the default behavior, so `mark_as_read` being `nil` is the same as `true`.
    return if provider_config&.dig('mark_as_read') == false

    recipient_id = if provider == 'zapi'
                     conversation.contact.phone_number
                   else
                     conversation.contact.identifier || conversation.contact.phone_number
                   end

    provider_service.read_messages(messages, recipient_id: recipient_id)
  end

  def unread_conversation(conversation)
    return unless provider_service.respond_to?(:unread_message)

    # NOTE: For the Baileys provider, the last message is required even if it is an outgoing message.
    last_message = conversation.messages.last
    provider_service.unread_message(conversation.contact.phone_number, last_message) if last_message
  end

  def disconnect_channel_provider
    provider_service.disconnect_channel_provider
  rescue StandardError => e
    # NOTE: Don't prevent destruction if disconnect fails
    Rails.logger.error "Failed to disconnect channel provider: #{e.message}"
  end

  # rubocop:disable Metrics/MethodLength, Metrics/AbcSize, Metrics/BlockLength
  def convert_provider!(new_provider:, new_provider_config:)
    # Serialize concurrent conversions of the same inbox. Without the lock,
    # two admin requests could both pass pre-validation, race the disconnect
    # and save, and leave webhooks/templates mismatched with the persisted
    # provider. `with_lock` issues SELECT FOR UPDATE and wraps the block in
    # a transaction; the loser waits until the winner commits.
    with_lock do
      previous_provider = provider
      previous_provider_config = provider_config.deep_dup
      normalized_new_config = new_provider_config || {}

      if new_provider == previous_provider
        errors.add(:provider, 'must be different from the current provider')
        raise ActiveRecord::RecordInvalid, self
      end

      # Pre-validate the new config without persisting, so we never terminate
      # the current provider session for a known-bad target config.
      assign_attributes(provider: new_provider, provider_config: normalized_new_config)
      unless valid?
        assign_attributes(provider: previous_provider, provider_config: previous_provider_config)
        raise ActiveRecord::RecordInvalid, self
      end
      # Snapshot provider_config AFTER valid? so we keep any fields populated
      # by before_validation callbacks (e.g. ensure_webhook_verify_token). The
      # final persist uses save!(validate: false), so we must not rely on a
      # second validation pass to replay those callbacks.
      validated_new_config = provider_config.deep_dup

      # Validation passed. Restore the old state briefly so the disconnect
      # call talks to the correct (old) endpoint, then reapply and persist
      # the new state. We call the service directly so a failed disconnect
      # propagates and aborts the conversion instead of silently leaving the
      # old session alive while the inbox points at the new provider.
      assign_attributes(provider: previous_provider, provider_config: previous_provider_config)
      # When converting away from whatsapp_cloud, mirror the destroy-time
      # cleanup so the Meta webhook subscription is torn down (embedded_signup
      # source); manual-setup channels follow the same no-op behavior as on
      # destruction. A teardown failure on a best-effort cleanup should not
      # abort the swap.
      if previous_provider == 'whatsapp_cloud'
        begin
          teardown_webhooks
        rescue StandardError => e
          Rails.logger.error "[WHATSAPP] Pre-conversion webhook teardown failed: #{e.message}"
        ensure
          # Reset the destroy-time guard so a later destroy! or subsequent
          # conversion on the same instance doesn't skip webhook removal.
          @webhook_teardown_initiated = false
        end
      end
      provider_service.disconnect_channel_provider if provider_service.respond_to?(:disconnect_channel_provider)

      assign_attributes(
        provider: new_provider,
        provider_config: validated_new_config,
        provider_connection: {},
        message_templates: {},
        message_templates_last_updated: nil
      )
      # Skip revalidation: the pre-flight valid? above is authoritative. A
      # second validate_provider_config? call here would re-hit the external
      # API and a transient failure could roll back the transaction after we
      # already disconnected the old session.
      save!(validate: false)

      setup_webhooks if should_auto_setup_webhooks?

      begin
        sync_templates
      rescue StandardError => e
        # Some provider sync_templates implementations stamp
        # `message_templates_last_updated` before the remote fetch. If the
        # fetch blows up, reset both columns so the inbox doesn't look
        # synced with zero templates and the scheduler will retry.
        update_columns(message_templates: {}, message_templates_last_updated: nil) # rubocop:disable Rails/SkipsModelValidations
        Rails.logger.error "[WHATSAPP] Post-conversion template sync failed: #{e.message}"
      end
    end

    self
  end
  # rubocop:enable Metrics/MethodLength, Metrics/AbcSize, Metrics/BlockLength

  def received_messages(messages, conversation)
    return unless provider_service.respond_to?(:received_messages)

    recipient_id = conversation.contact.identifier || conversation.contact.phone_number
    provider_service.received_messages(recipient_id, messages)
  end

  def on_whatsapp(phone_number)
    return unless provider_service.respond_to?(:on_whatsapp)

    provider_service.on_whatsapp(phone_number)
  end

  def delete_message(message, conversation:)
    return unless provider_service.respond_to?(:delete_message)

    recipient_id = if provider == 'zapi'
                     conversation.contact.phone_number.presence || conversation.contact.identifier
                   else
                     conversation.contact.identifier || conversation.contact.phone_number
                   end
    return if recipient_id.blank?

    provider_service.delete_message(recipient_id, message)
  end

  def edit_message(message, new_content, conversation:)
    return unless provider_service.respond_to?(:edit_message)

    recipient_id = conversation.contact.identifier || conversation.contact.phone_number
    provider_service.edit_message(recipient_id, message, new_content)
  end

  def sync_group(conversation, soft: false)
    return unless provider_service.respond_to?(:sync_group)

    provider_service.sync_group(conversation, soft: soft)
  end

  def allow_group_creation?
    provider_service.respond_to?(:allow_group_creation?) && provider_service.allow_group_creation?
  end

  delegate :setup_channel_provider, to: :provider_service
  delegate :import_session, to: :provider_service
  delegate :presence_subscribe, to: :provider_service
  delegate :send_message, to: :provider_service
  delegate :send_reaction_message, to: :provider_service
  delegate :send_template, to: :provider_service
  delegate :sync_templates, to: :provider_service
  delegate :media_url, to: :provider_service
  delegate :api_headers, to: :provider_service
  delegate :create_group, to: :provider_service
  delegate :update_group_subject, to: :provider_service
  delegate :update_group_description, to: :provider_service
  delegate :update_group_picture, to: :provider_service
  delegate :update_group_participants, to: :provider_service
  delegate :group_invite_code, to: :provider_service
  delegate :revoke_group_invite, to: :provider_service
  delegate :group_join_requests, to: :provider_service
  delegate :handle_group_join_requests, to: :provider_service
  delegate :group_leave, to: :provider_service
  delegate :group_setting_update, to: :provider_service
  delegate :group_join_approval_mode, to: :provider_service
  delegate :group_member_add_mode, to: :provider_service

  def setup_webhooks_on_create
    setup_webhooks if should_auto_setup_webhooks?
  end

  # Quem ganha webhook automatico na criacao:
  # - whatsapp_cloud em setup manual (no embedded signup quem chama e o
  #   EmbeddedSignupService, explicitamente)
  # - wuzapi, evolution e gowa: provedores do fork, configurados por
  #   perform_webhook_setup
  # 360dialog (default), baileys e zapi ficam de fora, como no upstream.
  def should_auto_setup_webhooks?
    return provider_config['source'] != 'embedded_signup' if provider == 'whatsapp_cloud'

    provider.in?(%w[wuzapi evolution gowa])
  end

  def setup_webhooks
    perform_webhook_setup
  rescue StandardError => e
    Rails.logger.error "[WHATSAPP] Webhook setup failed: #{e.message}"
    prompt_reauthorization!
  end

  private

  def webhook_configuration_changed?
    return true if saved_change_to_provider? && provider.in?(%w[wuzapi evolution gowa])
    return false unless provider.in?(%w[wuzapi evolution gowa])

    provider_webhook_configuration_changed?
  end

  def provider_webhook_configuration_changed?
    case provider
    when 'evolution'
      saved_change_to_evolution_api_token? || evolution_base_url_changed?
    when 'gowa'
      saved_change_to_gowa_username? || saved_change_to_gowa_password? || gowa_connection_config_changed?
    when 'wuzapi'
      saved_change_to_wuzapi_user_token? || wuzapi_base_url_changed?
    end
  end

  # Pushes the connection status to the account's agents over the websocket without
  # going through the full dispatcher, which would always enqueue an EventDispatcherJob
  # (wasteful for such a high-frequency event). Sync-only keeps it cheap.
  def broadcast_provider_connection_updated
    return if inbox.blank?

    Rails.configuration.dispatcher.sync_dispatcher.dispatch(
      Events::Types::INBOX_PROVIDER_CONNECTION_UPDATED, Time.zone.now,
      inbox: inbox, provider_connection: provider_connection
    )
  end

  def ensure_webhook_verify_token
    provider_config['webhook_verify_token'] ||= SecureRandom.hex(16) if provider.in?(%w[whatsapp_cloud baileys])
  end

  def move_tokens_to_encrypted_attributes
    move_evolution_token_to_encrypted_attribute
    move_gowa_credentials_to_encrypted_attributes
    return unless provider == 'wuzapi'

    move_wuzapi_user_token_to_encrypted_attribute
    move_wuzapi_admin_token_to_encrypted_attribute
  end

  def validate_provider_config
    errors.add(:provider_config, 'Invalid Credentials') unless provider_service.validate_provider_config?
  end

  def perform_webhook_setup
    return setup_wuzapi_webhook if provider == 'wuzapi'
    return setup_evolution_webhook if provider == 'evolution'
    return setup_gowa_webhook if provider == 'gowa'
    return provider_service.setup_channel_provider if provider_service.respond_to?(:setup_channel_provider)

    setup_default_webhook
  end

  def webhook_setup_service
    Whatsapp::WebhookSetupService.new(self, provider_config['business_account_id'], provider_config['api_key'])
  end

  def teardown_webhooks
    # Guarda do upstream: `has_one :inbox, dependent: :destroy` faz este callback
    # ser chamado em circulo na destruicao.
    return if @webhook_teardown_initiated

    @webhook_teardown_initiated = true
    return Whatsapp::WebhookTeardownService.new(self).perform unless provider.in?(%w[wuzapi evolution gowa])

    teardown_fork_provider_session
  end

  # Os provedores do fork derrubam sessao via HTTP no destroy; falha ali nao pode
  # impedir a exclusao da inbox, entao o erro fica registrado e a vida segue.
  def teardown_fork_provider_session
    case provider
    when 'wuzapi' then teardown_wuzapi_session
    when 'evolution' then teardown_evolution_session
    when 'gowa' then teardown_gowa_device
    end
  rescue StandardError => e
    Rails.logger.error "[WHATSAPP] Failed to teardown webhooks: #{e.message}"
  end

  def teardown_wuzapi_session
    return if provider_config['wuzapi_base_url'].blank?

    client = Wuzapi::Client.new(provider_config['wuzapi_base_url'])
    disconnect_wuzapi_user_session(client)
    delete_wuzapi_user_with_admin_token(client)
  end

  def provision_wuzapi_user
    return unless provider == 'wuzapi' && provider_config['auto_create_user']
    return if wuzapi_user_token.present?

    admin_token = wuzapi_admin_token
    base_url = provider_config['wuzapi_base_url']
    user_name = build_wuzapi_user_name
    result = provision_wuzapi_user_with_fallback(base_url, admin_token, user_name)
    provider_config['wuzapi_user_id'] = result[:wuzapi_user_id]
    self.wuzapi_user_token = result[:wuzapi_user_token]

    masked_token = result[:wuzapi_user_token].to_s[-4..]
    Rails.logger.info "Wuzapi User Provisioned. ID: #{result[:wuzapi_user_id]}, Token (last 4): ****#{masked_token}"
  end

  def teardown_evolution_session
    return if provider_config['evolution_base_url'].blank?

    client = EvolutionApi::Client.new(provider_config['evolution_base_url'], evolution_api_token)
    instance_name = "Chatwoot_#{phone_number}"

    begin
      client.logout_instance(instance_name)
    rescue StandardError => e
      Rails.logger.warn "Evolution Logout Failed: #{e.message}"
    end

    begin
      client.delete_instance(instance_name)
    rescue StandardError => e
      Rails.logger.warn "Evolution Delete Instance Failed: #{e.message}"
    end
  end

  def provision_evolution_instance
    return unless provider == 'evolution'
    return if evolution_api_token.blank?

    begin
      instance_name = "Chatwoot_#{phone_number}"
      client = EvolutionApi::Client.new(provider_config['evolution_base_url'], evolution_api_token)
      create_evolution_instance(client, instance_name)
      apply_evolution_instance_settings(client, instance_name)
      provider_config['evolution_instance_id'] = instance_name
    rescue StandardError => e
      Rails.logger.error "Evolution Provisioning failed: #{e.message}"
      errors.add(:base, "Evolution Provisioning Failed: #{e.message}")
      throw(:abort)
    end
  end

  def provision_gowa_device
    return unless provider == 'gowa'
    return if provider_config['gowa_device_id'].present?

    provider_config['webhook_secret'] ||= SecureRandom.hex(32)
    provider_config['gowa_device_id'] = provisioned_gowa_device_id
  rescue StandardError => e
    Rails.logger.error "GOWA provisioning falhou: #{e.message}"
    errors.add(:base, "Não foi possível preparar a conexão GOWA: #{e.message}")
    throw(:abort)
  end

  def move_evolution_token_to_encrypted_attribute
    return unless provider == 'evolution'
    return if provider_config['evolution_api_token'].blank?

    self.evolution_api_token = provider_config['evolution_api_token']
    provider_config.delete('evolution_api_token')
  end

  def move_gowa_credentials_to_encrypted_attributes
    return unless provider == 'gowa'

    self.gowa_username = provider_config.delete('gowa_username') if provider_config['gowa_username'].present?
    self.gowa_password = provider_config.delete('gowa_password') if provider_config['gowa_password'].present?
  end

  def move_wuzapi_user_token_to_encrypted_attribute
    return if provider_config['wuzapi_user_token'].blank?

    self.wuzapi_user_token = provider_config['wuzapi_user_token']
    provider_config.delete('wuzapi_user_token')
  end

  def move_wuzapi_admin_token_to_encrypted_attribute
    return if provider_config['wuzapi_admin_token'].blank?

    self.wuzapi_admin_token = provider_config['wuzapi_admin_token']
    provider_config.delete('wuzapi_admin_token')
  end

  def setup_wuzapi_webhook
    return if inbox.blank?
    return if wuzapi_user_token.blank?

    client = Wuzapi::Client.new(provider_config['wuzapi_base_url'])
    client.set_webhook(wuzapi_user_token, wuzapi_webhook_url)
  rescue StandardError => e
    Rails.logger.error "Wuzapi Webhook Setup Failed: #{e.message}"
  end

  def setup_evolution_webhook
    return if inbox.blank?
    return if evolution_api_token.blank?

    client = EvolutionApi::Client.new(provider_config['evolution_base_url'], evolution_api_token)
    client.set_webhook("Chatwoot_#{phone_number}", evolution_webhook_url)
  rescue StandardError => e
    Rails.logger.error "Evolution Webhook Setup Failed: #{e.message}"
  end

  def setup_gowa_webhook
    return if inbox.blank? || gowa_username.blank? || gowa_password.blank?

    client = Gowa::Client.new(provider_config['gowa_base_url'], gowa_username, gowa_password)
    client.update_webhook(provider_config.fetch('gowa_device_id'), gowa_webhook_url, provider_config.fetch('webhook_secret'))
  rescue StandardError => e
    Rails.logger.error "GOWA webhook setup falhou: #{e.message}"
  end

  def setup_default_webhook
    business_account_id = provider_config['business_account_id']
    api_key = provider_config['api_key']
    Whatsapp::WebhookSetupService.new(self, business_account_id, api_key).perform
  end

  def wuzapi_webhook_url
    app_url = ENV['FRONTEND_URL'].presence || 'http://localhost:3000'
    webhook_phone = phone_number.to_s.gsub(/\D/, '')
    "#{app_url}/webhooks/whatsapp/#{webhook_phone}"
  end

  def evolution_webhook_url
    app_url = ENV['FRONTEND_URL'].presence || 'http://localhost:3000'
    "#{app_url}/webhooks/evolution/#{phone_number}"
  end

  def gowa_webhook_url
    app_url = ENV['FRONTEND_URL'].presence || 'http://localhost:3000'
    "#{app_url}/webhooks/gowa/#{inbox.id}"
  end

  def disconnect_wuzapi_user_session(client)
    return if wuzapi_user_token.blank?

    safely_with_wuzapi_log('Logout') { client.session_logout(wuzapi_user_token) }
    safely_with_wuzapi_log('Disconnect') { client.session_disconnect(wuzapi_user_token) }
  end

  def delete_wuzapi_user_with_admin_token(client)
    return unless wuzapi_admin_token.present? && provider_config['wuzapi_user_id'].present?

    safely_with_wuzapi_log('Delete User') do
      client.delete_user(wuzapi_admin_token, provider_config['wuzapi_user_id'])
    end
  end

  def teardown_gowa_device
    return if provider_config['gowa_base_url'].blank? || provider_config['gowa_device_id'].blank?

    client = Gowa::Client.new(provider_config['gowa_base_url'], gowa_username, gowa_password)
    client.logout(provider_config['gowa_device_id'])
    client.delete_device(provider_config['gowa_device_id'])
  rescue StandardError => e
    Rails.logger.warn "GOWA cleanup falhou: #{e.message}"
  end

  def safely_with_wuzapi_log(action)
    yield
  rescue StandardError => e
    Rails.logger.warn "Wuzapi #{action} Failed: #{e.message}"
  end

  def build_wuzapi_user_name
    raw_name = inbox&.name || inbox_name_for_provisioning
    sanitized_inbox_name = raw_name.to_s.gsub(/[^a-zA-Z0-9]/, '_')
    prefix = sanitized_inbox_name.presence || 'Chatwoot'
    "#{prefix}_#{phone_number}"
  end

  def build_gowa_device_id
    "chatwoot-#{account_id}-#{phone_number.to_s.gsub(/\D/, '')}"
  end

  def gowa_connection_config_changed?
    before = provider_config_before_last_save || {}
    provider_config['gowa_base_url'] != before['gowa_base_url'] ||
      provider_config['gowa_device_id'] != before['gowa_device_id']
  end

  def evolution_base_url_changed?
    saved_change_to_provider_config? && provider_config['evolution_base_url'] != provider_config_before_last_save['evolution_base_url']
  end

  def wuzapi_base_url_changed?
    saved_change_to_provider_config? && provider_config['wuzapi_base_url'] != provider_config_before_last_save['wuzapi_base_url']
  end

  def provisioned_gowa_device_id
    response = Gowa::Client.new(provider_config['gowa_base_url'], gowa_username, gowa_password).create_device(build_gowa_device_id)
    response.dig('results', 'id') || build_gowa_device_id
  end

  def provision_wuzapi_user_with_fallback(base_url, admin_token, user_name)
    provision_wuzapi_user_for_url(base_url, admin_token, user_name)
  rescue StandardError => e
    handle_wuzapi_provision_failure(base_url, admin_token, user_name, e)
  end

  def provision_wuzapi_user_for_url(url, admin_token, user_name)
    service = Wuzapi::ProvisioningService.new(url, admin_token)
    service.provision(user_name)
  end

  def handle_wuzapi_provision_failure(base_url, admin_token, user_name, error)
    Rails.logger.warn "Wuzapi Provisioning failed with URL #{base_url}: #{error.message}"
    raise error unless base_url.match?(%r{/api/?$})

    fallback_url = base_url.gsub(%r{/api/?$}, '')
    Rails.logger.info "Retrying Wuzapi Provisioning with fallback URL: #{fallback_url}"
    result = provision_wuzapi_user_for_url(fallback_url, admin_token, user_name)
    provider_config['wuzapi_base_url'] = fallback_url
    Rails.logger.info "Wuzapi Provisioning fallback successful. Updated base_url to #{fallback_url}"
    result
  rescue StandardError => e
    Rails.logger.error "Wuzapi Provisioning fallback also failed: #{e.message}"
    errors.add(:base, "Wuzapi Provisioning Failed: #{e.message}")
    throw(:abort)
  end

  def create_evolution_instance(client, instance_name)
    client.create_instance(instance_name)
  rescue StandardError => e
    Rails.logger.warn "Evolution Create Instance failed (might already exist): #{e.message}"
  end

  def apply_evolution_instance_settings(client, instance_name)
    evolution_settings = provider_config['settings']
    return unless evolution_settings.is_a?(Hash)

    client.set_settings(instance_name, { 'alwaysOnline' => to_boolean(evolution_settings['always_online']) })
    client.set_instance_settings(instance_name, evolution_instance_settings_payload(evolution_settings))
  rescue StandardError => e
    Rails.logger.warn "Evolution Apply Settings failed: #{e.message}"
  end

  def evolution_instance_settings_payload(evolution_settings)
    {
      'rejectCall' => to_boolean(evolution_settings['reject_call']),
      'readMessages' => to_boolean(evolution_settings['read_messages']),
      'ignoreGroups' => to_boolean(evolution_settings['ignore_groups']),
      'ignoreStatus' => to_boolean(evolution_settings['ignore_status'])
    }
  end

  def to_boolean(value)
    value == true || value == 'true'
  end
end
