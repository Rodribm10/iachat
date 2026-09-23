class Captain::Hermes::LocationFactReplyService
  LOCATION_INTENT = /\b(localizacao|endereco|maps|mapa|rota|como\s+chegar|onde\s+(?:fica|ficam|e))\b/i
  OTHER_INTENT = /
    \b(valor(?:es)?|preco(?:s)?|quanto|custa|pernoite|diaria|\d+\s*h|fotos?|videos?|
    suites?|quartos?|reserv\w*|vagas?|disponi\w*|pix|pagamento)\b
  /ix

  def initialize(profile_name:, content:)
    @profile_name = profile_name
    @content = content.to_s
  end

  def call
    return unless location_request?

    locations = selected_locations
    return if locations.empty?

    Captain::Hermes::KnownFactReply.new(
      kind: :location,
      content: format_reply(locations),
      exclusive: !normalized_content.match?(OTHER_INTENT)
    )
  end

  private

  def location_request?
    normalized_content.match?(LOCATION_INTENT)
  end

  def selected_locations
    locations = profile.fetch('locations', []).select { |location| valid_location?(location) }
    return locations if locations.one?

    matched = locations.select do |location|
      location.fetch('aliases', []).any? { |alias_name| alias_present?(alias_name) }
    end
    matched.presence || locations
  end

  def valid_location?(location)
    location['name'].present? && location['url'].to_s.start_with?('https://')
  end

  def alias_present?(alias_name)
    normalized_alias = normalize(alias_name)
    normalized_content.match?(/(?<![a-z0-9])#{Regexp.escape(normalized_alias)}(?![a-z0-9])/)
  end

  def format_reply(locations)
    return "Claro 😊 Localização do #{locations.first.fetch('name')}: #{locations.first.fetch('url')}" if locations.one?

    lines = locations.map { |location| "• #{location.fetch('name')}: #{location.fetch('url')}" }
    "Claro 😊 Nossas localizações:\n#{lines.join("\n")}"
  end

  def profile
    @profile ||= Captain::Hermes::KnownFactsCatalog.profile(@profile_name)
  end

  def normalized_content
    @normalized_content ||= normalize(@content)
  end

  def normalize(text)
    ActiveSupport::Inflector.transliterate(text.to_s.downcase).squish
  end
end
