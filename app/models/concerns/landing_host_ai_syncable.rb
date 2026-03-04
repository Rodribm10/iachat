# frozen_string_literal: true
require 'digest'

module LandingHostAiSyncable
  extend ActiveSupport::Concern
  SYNC_METADATA_KEY = 'landing_promotion_sync'.freeze

  included do
    after_save :sync_promotion_to_faq
  end

  def sync_promotion_to_faq
    return unless custom_config.is_a?(Hash)
    return cleanup_all_synced_knowledge unless can_sync_to_portal?

    active_entries = extract_promotions.each_with_index.filter_map do |promotion, index|
      next unless promotion_active?(promotion)

      {
        promotion: promotion,
        signature: promotion_signature(promotion, index)
      }
    end

    sync_active_promotions(active_entries)
    cleanup_stale_synced_knowledge(active_entries.map { |entry| entry[:signature] })
    cleanup_legacy_aggregated_sync
  end

  private

  def extract_promotions
    promotions = custom_config['promotions']
    promotions = [custom_config['promotion']] if promotions.blank? && custom_config['promotion'].is_a?(Hash)
    Array(promotions).select { |promotion| promotion.is_a?(Hash) }
  end

  def sync_active_promotions(active_entries)
    active_entries.each do |entry|
      article = create_or_update_promotion_article(entry)
      sync_captain_document(article, entry)
    end
  end

  def create_or_update_promotion_article(entry)
    article = find_synced_article(entry[:signature]) || portal.articles.new(account_id: inbox.account_id)
    article.title = promotion_article_title(entry[:promotion], entry[:signature])
    article.content = generate_promotion_text(entry[:promotion])
    article.description = "FAQ Gerado automaticamente pela Landing Page: #{hostname}"
    article.meta = (article.meta || {}).merge(sync_metadata_for(signature: entry[:signature]))
    article.author ||= default_article_author
    article.status = :published
    article.save!
    article
  end

  def generate_promotion_text(promo)
    text = %(INSTRUÇÃO PARA A IA (PROMOÇÃO ATIVA DO LINK #{hostname}):\n\n)
    text += %(Existe uma promoção ativa para os leads que chegam pela landing page '#{hostname}'.\n)
    text += %(Ofereça a promoção correspondente ao Canal/Origem pelo qual o cliente chegou.\n\n)

    channel = promo['channel'].presence || 'Geral'
    text += "--- CANAL / ORIGEM: #{channel} ---\n"
    text += "Título da Promoção: #{promo['title']}\n" if promo['title'].present?
    text += "Condições / Descrição: #{promo['description']}\n" if promo['description'].present?
    text += "Cupom: #{promo['coupon_code']}\n" if promo['coupon_code'].present?
    text += "Válida até: #{promo['valid_until']}\n" if promo['valid_until'].present?
    text
  end

  def cleanup_stale_synced_knowledge(active_signatures)
    synced_articles.find_each do |article|
      signature = article.meta&.dig(SYNC_METADATA_KEY, 'promotion_signature')
      next if signature.present? && active_signatures.include?(signature)

      delete_synced_captain_document(article)
      article.destroy!
    end

    return unless captain_assistant.present? && defined?(Captain::Document)

    synced_documents.find_each do |document|
      signature = document.metadata&.dig(SYNC_METADATA_KEY, 'promotion_signature')
      next if signature.present? && active_signatures.include?(signature)

      document.destroy!
    end
  end

  def cleanup_legacy_aggregated_sync
    legacy_article = portal.articles.find_by(
      "meta -> '#{SYNC_METADATA_KEY}' ->> 'landing_host_id' = ? AND (meta -> '#{SYNC_METADATA_KEY}' ->> 'promotion_signature') IS NULL",
      id.to_s
    )

    return if legacy_article.blank?

    delete_synced_captain_document(legacy_article)
    legacy_article.destroy!
  end

  def cleanup_all_synced_knowledge
    cleanup_stale_synced_knowledge([])
    cleanup_legacy_aggregated_sync
  end

  def find_synced_article(signature)
    portal.articles.find_by(
      "meta -> '#{SYNC_METADATA_KEY}' ->> 'landing_host_id' = ? AND meta -> '#{SYNC_METADATA_KEY}' ->> 'promotion_signature' = ?",
      id.to_s,
      signature
    )
  end

  def synced_articles
    portal.articles.where("meta -> '#{SYNC_METADATA_KEY}' ->> 'landing_host_id' = ?", id.to_s)
  end

  def sync_captain_document(article, entry)
    return unless captain_assistant.present? && defined?(Captain::Document)

    publication_url = article_public_url(article)
    document = find_synced_document(entry[:signature], article)
    document ||= captain_assistant.documents.new(external_link: article_public_url(article))

    document.external_link = publication_url
    document.name = article.title
    document.content = article.content
    document.status = :available
    document.metadata = (document.metadata || {})
                      .merge(sync_metadata_for(signature: entry[:signature]))
                      .merge('article_id' => article.id)
    document.save!
  end

  def find_synced_document(signature, article)
    by_article = captain_assistant.documents.find_by("metadata ->> 'article_id' = ?", article.id.to_s)
    return by_article if by_article.present?

    captain_assistant.documents.find_by(external_link: article_public_url(article))
  end

  def delete_synced_captain_document(article)
    return unless captain_assistant.present? && defined?(Captain::Document)

    signature = article.meta&.dig(SYNC_METADATA_KEY, 'promotion_signature')

    document = captain_assistant.documents.find_by("metadata ->> 'article_id' = ?", article.id.to_s)
    document ||= captain_assistant.documents.find_by(
      "metadata -> '#{SYNC_METADATA_KEY}' ->> 'landing_host_id' = ? AND metadata -> '#{SYNC_METADATA_KEY}' ->> 'promotion_signature' = ?",
      id.to_s,
      signature
    ) if signature.present?
    document ||= captain_assistant.documents.find_by(external_link: article_public_url(article))
    document&.destroy!
  end

  def synced_documents
    return Captain::Document.none unless captain_assistant.present? && defined?(Captain::Document)

    captain_assistant.documents.where("metadata -> '#{SYNC_METADATA_KEY}' ->> 'landing_host_id' = ?", id.to_s)
  end

  def promotion_article_title(promo, signature)
    promo_title = promo['title'].to_s.strip
    promo_title = "Promoção #{signature[0, 8].upcase}" if promo_title.blank?
    "Promoção Automática - #{hostname.upcase} | #{promo_title}".truncate(220)
  end

  def promotion_signature(promotion, index)
    payload = {
      channel: promotion['channel'].to_s.strip,
      title: promotion['title'].to_s.strip,
      description: promotion['description'].to_s.strip,
      coupon_code: promotion['coupon_code'].to_s.strip,
      valid_until: promotion['valid_until'].to_s.strip,
      position: index
    }

    Digest::SHA256.hexdigest(payload.to_json)
  end

  def portal
    inbox.portal
  end

  def can_sync_to_portal?
    inbox.present? && inbox.portal_id.present?
  end

  def promotion_active?(promotion)
    return false unless promotion.is_a?(Hash)
    return false unless promotion['active']
    return false if promotion_expired?(promotion['valid_until'])

    true
  end

  def promotion_expired?(raw_date)
    parsed_date = parse_valid_until(raw_date)
    parsed_date.present? && parsed_date < Time.zone.today
  end

  def parse_valid_until(raw_date)
    return if raw_date.blank?

    value = raw_date.to_s.strip

    Date.strptime(value, '%d/%m/%Y')
  rescue ArgumentError
    Date.iso8601(value)
  rescue ArgumentError
    Date.parse(value)
  rescue ArgumentError
    nil
  end

  def captain_assistant
    return unless inbox.respond_to?(:captain_assistant)

    inbox.captain_assistant
  end

  def sync_metadata_for(signature:)
    {
      SYNC_METADATA_KEY => {
        'source' => 'landing_host_promotions',
        'landing_host_id' => id,
        'inbox_id' => inbox_id,
        'hostname' => hostname,
        'promotion_signature' => signature
      }
    }
  end

  def article_public_url(article)
    base_url = portal.custom_domain.present? ? custom_domain_url_base : frontend_url_base
    "#{base_url}/hc/#{portal.slug}/articles/#{article.slug}"
  end

  def custom_domain_url_base
    frontend_uri = URI.parse(ENV.fetch('FRONTEND_URL', 'https://app.chatwoot.com'))
    "#{frontend_uri.scheme}://#{portal.custom_domain}"
  rescue URI::InvalidURIError
    "https://#{portal.custom_domain}"
  end

  def frontend_url_base
    base = ENV.fetch('HELPCENTER_URL', '').presence || ENV.fetch('FRONTEND_URL', '')
    base.delete_suffix('/')
  end

  def default_article_author
    # Assumes that the account has at least one user (owner/admin) to author the article
    inbox.account.users.order(id: :asc).first
  end
end
