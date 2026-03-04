# frozen_string_literal: true

module LandingHostAiSyncable
  extend ActiveSupport::Concern

  included do
    after_save :sync_promotion_to_faq
  end

  def sync_promotion_to_faq
    return unless custom_config.is_a?(Hash)

    promotions = custom_config['promotions']

    # Fallback to legacy format if array is empty but object exists
    promotions = [custom_config['promotion']] if promotions.blank? && custom_config['promotion'].is_a?(Hash)

    active_promos = Array(promotions).select { |p| p.is_a?(Hash) && p['active'] }

    if active_promos.any?
      create_or_update_faq_article(active_promos)
    else
      archive_faq_article
    end
  end

  private

  def create_or_update_faq_article(promos)
    return unless can_sync_to_portal?

    article = find_or_initialize_faq_article
    article.title = faq_article_title

    # Generating the standard AI instruction text for the multiple promotions
    text = %(INSTRUÇÃO PARA A IA (PROMOÇÕES ATIVAS DO LINK #{hostname}):\n\n)
    text += %(Existem promoções ativas para os leads que chegam pela landing page '#{hostname}'.\n)
    text += %(Ofereça a promoção correspondente ao Canal/Origem pelo qual o cliente chegou.\n\n)

    promos.each do |promo|
      channel = promo['channel'].presence || 'Geral'
      text += "--- CANAL / ORIGEM: #{channel} ---\n"
      text += "Título da Promoção: #{promo['title']}\n" if promo['title'].present?
      text += "Condições / Descrição: #{promo['description']}\n" if promo['description'].present?
      text += "Cupom: #{promo['coupon_code']}\n" if promo['coupon_code'].present?
      text += "Válida até: #{promo['valid_until']}\n" if promo['valid_until'].present?
      text += "\n"
    end

    article.content = text
    article.description = "FAQ Gerado automaticamente pela Landing Page: #{hostname}"
    # Setting the author as the portal's account first user (just as a fallback) or we can use a system user
    article.author ||= default_article_author
    article.status = :published

    article.save!
  end

  def archive_faq_article
    return unless can_sync_to_portal?

    article = find_faq_article
    article&.update!(status: :archived)
  end

  def find_or_initialize_faq_article
    find_faq_article || portal.articles.new(account_id: inbox.account_id)
  end

  def find_faq_article
    portal.articles.find_by(title: faq_article_title)
  end

  def faq_article_title
    "Promoção Automática - #{hostname.upcase}"
  end

  def portal
    inbox.portal
  end

  def can_sync_to_portal?
    inbox.present? && inbox.portal_id.present?
  end

  def default_article_author
    # Assumes that the account has at least one user (owner/admin) to author the article
    inbox.account.users.order(id: :asc).first
  end
end
