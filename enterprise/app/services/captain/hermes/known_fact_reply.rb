class Captain::Hermes::KnownFactReply
  attr_reader :kind, :content

  def initialize(kind:, content:, exclusive:)
    @kind = kind.to_sym
    @content = content
    @exclusive = exclusive
  end

  def exclusive?
    @exclusive
  end

  def external_source
    "hermes_known_fact_#{kind}"
  end
end
