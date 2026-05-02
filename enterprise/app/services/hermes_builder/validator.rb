# Validação de saúde de um agente Hermes — porta dos checks DB/runtime do
# script CLI `bin/hermes-validate` pro contexto Rails (consumido pela aba
# "Verificação" no Construtor UI).
#
# Cobre: configuração do Captain::Assistant, mapeamento CaptainInbox/Unit,
# pricing dry-run, credenciais Inter, registry MCP, humanização. NÃO cobre
# filesystem (SOUL.md/SKILL.md/config.yaml) nem systemd — esses ficam pro
# CLI (rodar no shell da VPS) porque o container Rails não tem visibilidade
# do `/root/.hermes/profiles/` do host.
#
# Cada check tem `repair_id` opcional — quando setado, indica que existe
# handler em HermesBuilder::Repairer pra ressincronizar/corrigir o estado
# (ex: sync_captain_inbox_unit, set_engine_hermes, set_default_typing).
class HermesBuilder::Validator
  EXPECTED_MCP_TOOLS = %w[
    generate_pix faq_lookup add_label send_suite_images react_to_message
    update_contact get_contact_history check_pix_payment reschedule_reservation
  ].freeze

  Result = Struct.new(:label, :status, :detail, :repair_id, :category, keyword_init: true) do
    def to_h
      { label: label, status: status, detail: detail.to_s, repair_id: repair_id, category: category }
    end
  end

  def self.run(slug)
    new(slug).call
  end

  def initialize(slug)
    @slug = slug.to_s.strip
    @results = []
  end

  def call
    asst = ::Captain::Assistant.find_by(hermes_profile_name: @slug, engine: 'hermes')
    if asst.nil?
      add('Captain::Assistant existe', 'FAIL', "Nenhum assistant com hermes_profile_name='#{@slug}'", category: 'db')
      return summary
    end

    @asst = asst
    @ci = ::CaptainInbox.where(captain_assistant_id: asst.id).first
    @inbox = @ci&.inbox
    @unit = asst.captain_unit

    check_db
    check_pricing
    check_routing
    check_humanization
    check_mcp_tools
    summary
  end

  private

  def check_db
    check_db_engine
    check_db_endpoint
    check_db_unit_consistency
  end

  def check_db_engine
    add('engine=hermes', pf(@asst.engine == 'hermes'), @asst.engine,
        repair_id: 'set_engine_hermes', category: 'db')
    add('hermes_profile_name setado', pf(@asst.hermes_profile_name.present?),
        @asst.hermes_profile_name, category: 'db')
    add('parent_assistant_id setado', pw(@asst.parent_assistant_id.present?),
        "parent=#{@asst.parent_assistant_id}", category: 'db')
  end

  def check_db_endpoint
    add('hermes_port setado', pf(@asst.hermes_port.present?),
        "port=#{@asst.hermes_port}", category: 'db')
    add('hermes_subscription_secret setado', pf(@asst.hermes_subscription_secret.present?),
        @asst.hermes_subscription_secret.present? ? 'presente' : 'vazio', category: 'db')
    add('hermes_webhook_base_url', pf(@asst.hermes_webhook_base_url.to_s.start_with?('http')),
        @asst.hermes_webhook_base_url, category: 'db')
  end

  def pf(bool) = bool ? 'PASS' : 'FAIL'
  def pw(bool) = bool ? 'PASS' : 'WARN'

  def check_db_unit_consistency
    add('captain_unit_id setado', @asst.captain_unit_id.present? ? 'PASS' : 'FAIL',
        @unit&.name, category: 'db')

    ci_unit = @ci&.captain_unit_id
    sync_ok = @asst.captain_unit_id.present? && ci_unit == @asst.captain_unit_id
    add('CaptainInbox.unit == Assistant.unit', sync_ok ? 'PASS' : 'FAIL',
        "asst=#{@asst.captain_unit_id} ci=#{ci_unit}",
        repair_id: sync_ok ? nil : 'sync_captain_inbox_unit', category: 'db')

    add('Brand resolvida', @unit&.brand.present? ? 'PASS' : 'FAIL', @unit&.brand&.name, category: 'db')
    add('CaptainInbox mapeada', @inbox.present? ? 'PASS' : 'WARN', "inbox=#{@inbox&.id}", category: 'db')
  end

  def check_pricing
    cats = (@unit&.pricing_categories&.includes(:amounts)&.to_a) || []
    add('Pricing categorias > 0', cats.any? ? 'PASS' : 'FAIL',
        "#{cats.size} cats: #{cats.map(&:key).join(',')}", category: 'pricing')
    add('Pricing amounts > 0', cats.flat_map { |c| c.amounts.to_a }.size.positive? ? 'PASS' : 'FAIL',
        "#{cats.flat_map { |c| c.amounts.to_a }.size} amounts", category: 'pricing')

    check_pricing_dry_run(cats)
    check_inter_creds
  end

  def check_pricing_dry_run(cats)
    return if cats.empty?

    first_cat = cats.first.key
    res = ::Captain::Mcp::PricingTables.calculate(
      unit_id: @unit.id, suite_category: first_cat,
      period: 'pernoite_promo', total_guests: 2
    )
    if res[:error]
      add('Pricing dry-run', 'FAIL', "ERR: #{res[:error]}", category: 'pricing')
    else
      add('Pricing dry-run', 'PASS', "OK R$ #{res[:amount]} (#{first_cat}/pernoite)", category: 'pricing')
    end
  end

  def check_inter_creds
    inter_ok = @unit.present? && @unit.respond_to?(:inter_credentials_present?) && @unit.inter_credentials_present?
    add('Credenciais Inter completas', pw(inter_ok),
        inter_ok ? 'cert+key+client_id presentes' : 'faltam — generate_pix cai no fallback',
        category: 'pricing')
  end

  def check_routing
    if @inbox.blank?
      add('Captain::Hermes.enabled_for?', 'WARN', 'sem inbox mapeada', category: 'routing')
      return
    end

    enabled = ::Captain::Hermes.enabled_for?(@inbox)
    add('Captain::Hermes.enabled_for?', enabled ? 'PASS' : 'FAIL', enabled.to_s, category: 'routing')

    url = ::Captain::Hermes.webhook_url_for(@inbox).to_s
    expected_suffix = "/webhooks/captain-inbox-#{@slug}"
    add('webhook_url aponta pra slug', url.end_with?(expected_suffix) ? 'PASS' : 'FAIL',
        url, category: 'routing')

    secret = ::Captain::Hermes.subscription_signing_secret(@inbox).to_s
    add('subscription_signing_secret presente', secret.present? ? 'PASS' : 'FAIL',
        secret.present? ? "#{secret.first(8)}..." : 'vazio', category: 'routing')
  end

  def check_humanization
    typing_delay = @inbox.respond_to?(:typing_delay) ? @inbox.typing_delay.to_i : 0
    add('Inbox.typing_delay > 0 (debounce)', typing_delay.positive? ? 'PASS' : 'WARN',
        "#{typing_delay}s",
        repair_id: typing_delay.positive? ? nil : 'set_default_typing_delay',
        category: 'humanization')

    mode = @asst.config.to_h.dig('response_delay', 'mode')
    add('config.response_delay (typing simulation)', mode == 'typing_simulation' ? 'PASS' : 'WARN',
        mode || 'none',
        repair_id: mode == 'typing_simulation' ? nil : 'set_default_response_delay',
        category: 'humanization')

    gallery_count = @unit&.gallery_items&.count || 0
    add('GalleryItem para fotos', gallery_count.positive? ? 'PASS' : 'WARN',
        "#{gallery_count} items (send_suite_images precisa)", category: 'humanization')
  end

  def check_mcp_tools
    registered = mcp_tool_names
    EXPECTED_MCP_TOOLS.each do |t|
      add("MCP tool '#{t}' registrado", registered.include?(t) ? 'PASS' : 'FAIL', nil, category: 'mcp')
    end
  end

  def mcp_tool_names
    ::Captain::Mcp::ToolRegistry::TOOLS.map(&:name)
  rescue StandardError
    []
  end

  def add(label, status, detail = nil, repair_id: nil, category: nil)
    @results << Result.new(label: label, status: status, detail: detail, repair_id: repair_id, category: category)
  end

  def summary
    pass = @results.count { |r| r.status == 'PASS' }
    fail_n = @results.count { |r| r.status == 'FAIL' }
    warn = @results.count { |r| r.status == 'WARN' }
    {
      slug: @slug,
      ok: fail_n.zero?,
      total: @results.size,
      pass: pass,
      fail: fail_n,
      warn: warn,
      results: @results.map(&:to_h)
    }
  end
end
