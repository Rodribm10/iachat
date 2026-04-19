class Captain::ContactMemories::PromptInjectionService
  def initialize(memories:)
    @memories = memories
  end

  def call
    return '' if @memories.blank?

    lines = @memories.map do |memory|
      %(  <#{memory.memory_type} confidence="#{format('%.2f', memory.confidence)}">#{escape(memory.content)}</#{memory.memory_type}>)
    end

    "<memoria_cliente>\n#{lines.join("\n")}\n</memoria_cliente>"
  end

  private

  def escape(text)
    text.to_s.gsub('&', '&amp;').gsub('<', '&lt;').gsub('>', '&gt;')
  end
end
