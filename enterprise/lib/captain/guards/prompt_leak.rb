# frozen_string_literal: true

# Detecta resposta de LLM que vazou conteúdo interno em vez de falar com o cliente.
#
# Duas famílias de padrão, endurecidas ao longo do tempo em produção:
#
#   SYSTEM_PROMPT — a resposta COMEÇA com pedaço do system prompt ("[Contexto]",
#   "<contexto>", "You are part of Captain,"). O LLM devolveu a própria instrução.
#
#   THOUGHT — em qualquer parte da mensagem aparece narração do que o assistente
#   deveria fazer ("a IA deve...", "quando o cliente pedir..."), nome técnico de
#   tool (`handoff_to_`, `daniela_reservas`), JSON cru ou Liquid não renderizado.
#   A resposta está DESCREVENDO o atendimento em vez de fazer o atendimento.
#
#   REFUSAL — o assistente ANUNCIA ao cliente que não vai responder ("Sem resposta
#   — a conversa permanece com a equipe humana após a transferência"). Silêncio é
#   uma decisão do Chatwoot, não do modelo: se a mensagem chegou até ele, é porque
#   a conversa está no funil da IA. Quando o modelo decide calar mesmo assim, ele
#   não fica em silêncio — o protocolo do Hermes sempre devolve texto —, então
#   escreve o relatório da decisão e o cliente lê. Visto na conv 126 da conta 2 em
#   25/08/2026: a Duda tinha chamado `handoff` às 11:44, a conversa foi devolvida
#   pra `pending`, e às 18:35 e 18:53 ela respondeu ao cliente que não responderia.
#
# Até 22/08/2026 isso vivia dentro de Captain::Conversation::ResponseBuilderJob e
# portanto só protegia o motor interno do Captain — que não atende ninguém em
# produção. O caminho real (Hermes) tinha só as guardas de erro técnico, nascidas
# do incidente de 25/07/2026 em que clientes do Instagram leram "HTTP 401".
# Extraído para cá para valer nos dois caminhos.
module Captain::Guards::PromptLeak
  SYSTEM_PROMPT_PATTERNS = [
    /\A\[Contexto\]/i,
    /\A<contexto>/i,
    /\A#\s*System Context/i,
    /\A\[Identity\]/i,
    /\A\[Context\]/i,
    /\AYou are part of Captain,/i
  ].freeze

  THOUGHT_PATTERNS = [
    # Narração em terceira pessoa sobre o próprio assistente
    /\b(jasmine|a\s+ia|o\s+assistente|o\s+bot)\s+(deve|deveria|precisa|tem\s+que|nunca\s+deve|n[ãa]o\s+deve)\b/i,
    # Instrução condicional vazada
    /\bquando\s+o\s+cliente\s+(fa[zç]er|disser|pedir|perguntar|falar|usar|mencionar|informar)\b/i,
    # Comandos imperativos pra IA disfarçados de resposta
    /\b(busque|consulte|acione|chame|use)\s+(a\s+)?ferramenta\b/i,
    /\b(passe|envie|repasse)\s+para\s+(ele|ela|o\s+cliente)\b/i,
    # Nomes técnicos de tools/handoffs nunca devem aparecer ao cliente
    /\bhandoff_to_/i,
    /\bcaptain--tools--/i,
    /\b(daniela_reservas|maria_fotos|disponibilidade_suites|outras_unidades)\b/i,
    /\bhandoff_imediato\b/i,
    # Descrições meta de fluxo
    /\b(fluxo\s+correto|gatilhos?\s+de\s+exemplo|antes\s+de\s+responder|antes\s+de\s+gerar)\b/i,
    # JSON cru / blocos de schema
    /\A\s*[{\[]/,
    /"reasoning"\s*:/,
    /"reaction_emoji"\s*:/,
    # Liquid não renderizado
    /\{\{\s*\w+\s*\}\}/,
    /\{%\s*\w+/
  ].freeze

  # Recusa narrada. Barrar aqui NÃO é cosmético: o callback manda a conversa para
  # triagem humana, então falso positivo cala a IA e chama gente à toa. Por isso
  # cada padrão é ancorado no que só existe como relato de bastidor — e "humana"
  # dito ao cliente já é bastidor por definição. Fora, de propósito:
  # "após a transferência" (transferência bancária é assunto diário: "após a
  # transferência, me manda o comprovante") e "conforme o fluxo" (existe fluxo
  # legítimo de matrícula). Os dois casos reais já são pegos pelos padrões abaixo.
  REFUSAL_PATTERNS = [
    /\A\s*(sem|nenhuma)\s+resposta\b/i,
    /\bn[ãa]o\s+(vou|devo)\s+responder\b/i,
    /\bn[ãa]o\s+envio\s+(novas\s+)?mensagens\b/i,
    /\b(permanece|segue|continua|fica)\s+com\s+(a\s+)?(equipe|atendimento)\s+human[ao]\b/i,
    /\btransferid[ao]\s+para\s+(a\s+)?(equipe|atendimento)\s+human[ao]\b/i
  ].freeze

  ALL_PATTERNS = (SYSTEM_PROMPT_PATTERNS + THOUGHT_PATTERNS + REFUSAL_PATTERNS).freeze

  module_function

  # true quando a resposta não pode ser entregue ao cliente.
  def leak?(content)
    normalized = normalize(content)
    return false if normalized.blank?

    ALL_PATTERNS.any? { |pattern| normalized.match?(pattern) }
  end

  # Qual família disparou — usado na nota interna, pra equipe entender o motivo
  # sem precisar ler a regex.
  def reason(content)
    normalized = normalize(content)
    return nil if normalized.blank?
    return 'system_prompt' if SYSTEM_PROMPT_PATTERNS.any? { |p| normalized.match?(p) }
    return 'pensamento_interno' if THOUGHT_PATTERNS.any? { |p| normalized.match?(p) }
    return 'recusa_de_resposta' if REFUSAL_PATTERNS.any? { |p| normalized.match?(p) }

    nil
  end

  def normalize(content)
    content.is_a?(String) ? content.strip : content.to_s.strip
  end
end
