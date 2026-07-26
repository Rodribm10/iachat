# Juiz automático das FAQs aprendidas de conversas com triagem humana.
#
# Substitui a aprovação manual: quando a IA não sabe e o humano responde, a
# resposta humana é conteúdo validado — mas nem tudo que o humano escreve pode
# virar conhecimento permanente (preço negociado na hora, dado de um cliente
# específico, promessa fora da política). Este serviço aplica uma rubrica de 6
# critérios e decide entre quarentena (`trial`) e fila de exceção (`pending`).
#
# Critérios 1–4 são eliminatórios. Os critérios 5 e 6 não reprovam: o juiz pode
# reescrever a FORMA (formatação, tom) e nunca o CONTEÚDO — reescrita suspeita
# de alterar conteúdo é descartada em `safe_revision`.
class Captain::Llm::FaqJudgeService
  MAX_CONVERSATION_CHARS = 20_000
  MAX_NEIGHBOURS = 5

  ELIMINATORY_CRITERIA = %w[fidelidade generalizavel nao_contradiz politica].freeze

  # Uma reescrita fora desta faixa de tamanho quase certamente mudou conteúdo,
  # não só formatação. Nesse caso preservamos o texto original.
  REVISION_MIN_RATIO = 0.4
  REVISION_MAX_RATIO = 2.5

  def self.judge_model
    InstallationConfig.find_by(name: 'CAPTAIN_JUDGE_MODEL')&.value.presence ||
      Captain::Llm::ProviderConfig.light_model
  end

  def initialize(assistant:, question:, answer:, conversation:, neighbours: [])
    @assistant = assistant
    @question = question.to_s
    @answer = answer.to_s
    @conversation = conversation
    @neighbours = Array(neighbours).first(MAX_NEIGHBOURS)
  end

  def call
    parsed = JSON.parse(call_llm)
    build_verdict(parsed)
  rescue JSON::ParserError => e
    Rails.logger.warn("[Captain::FaqJudge] JSON parse: #{e.message}")
    failure("json_parse_error: #{e.message}")
  rescue StandardError => e
    Rails.logger.error("[Captain::FaqJudge] #{e.class}: #{e.message}")
    failure("llm_error: #{e.class}: #{e.message}")
  end

  private

  attr_reader :assistant, :question, :answer, :conversation, :neighbours

  def call_llm
    RubyLLM.chat(model: self.class.judge_model)
           .with_temperature(0)
           .with_params(response_format: { type: 'json_object' })
           .ask(build_prompt)
           .content.to_s
  end

  def build_verdict(parsed)
    approved = ELIMINATORY_CRITERIA.all? { |criterion| parsed.dig(criterion, 'aprovado') == true }

    {
      approved: approved,
      question: approved ? safe_revision(parsed['pergunta_revisada'], question) : question,
      answer: approved ? safe_revision(parsed['resposta_revisada'], answer) : answer,
      raw: parsed.merge('model' => self.class.judge_model, 'judged_at' => Time.current.iso8601)
    }
  end

  # O juiz só pode reescrever forma. Se o tamanho mudou demais, ele reescreveu
  # conteúdo — descartamos a revisão e ficamos com a resposta humana original.
  def safe_revision(revised, original)
    revised = revised.to_s.strip
    return original if revised.blank?

    ratio = revised.length.to_f / [original.length, 1].max
    return original if ratio < REVISION_MIN_RATIO || ratio > REVISION_MAX_RATIO

    revised
  end

  def failure(reason)
    {
      approved: false,
      question: question,
      answer: answer,
      raw: { 'erro' => reason, 'model' => self.class.judge_model, 'judged_at' => Time.current.iso8601 }
    }
  end

  def build_prompt
    <<~PROMPT
      Você é o revisor de qualidade da base de conhecimento de uma rede de hotéis.

      Uma atendente de IA não soube responder uma pergunta e passou o atendimento
      para um humano. O humano respondeu ao cliente, e essa resposta foi
      transformada na FAQ candidata abaixo. Sua missão é decidir se essa FAQ pode
      entrar na base de conhecimento que a IA usa para responder outros clientes.

      ## PRINCÍPIO

      A resposta do humano é considerada CORRETA em conteúdo — você não julga se
      ela está certa, o humano é a autoridade. Você julga se ela pode ser
      REAPROVEITADA com outros clientes. Uma resposta pode estar perfeita para
      aquele cliente e ser péssima como conhecimento permanente.

      ## CRITÉRIOS ELIMINATÓRIOS (reprovam a FAQ)

      1. **fidelidade** — a FAQ diz o que o humano de fato respondeu? Reprove se
         a FAQ inventou informação, extrapolou ou juntou coisas que o humano não
         disse. Reformatação é permitida; conteúdo novo não.

      2. **generalizavel** — vale para qualquer cliente que faça essa pergunta?
         REPROVE se contiver:
         - dado pessoal (nome, CPF, telefone, e-mail, número de reserva, endereço);
         - valor/desconto/condição negociado pontualmente ("pra você faço por 180",
           "vou abrir uma exceção", "como você é cliente antigo");
         - contexto exclusivo daquele atendimento ("a suíte que você viu ontem",
           "conforme combinamos");
         - informação com validade curta ou pontual (disponibilidade de hoje,
           promoção de um fim de semana específico).
         APROVE preço de tabela e política padrão — isso é conhecimento legítimo.

      3. **nao_contradiz** — a FAQ contradiz algum conhecimento já existente na
         base (listado abaixo)? Reprove se afirmar o oposto de um FAQ existente.
         Complementar ou detalhar não é contradizer.

      4. **politica** — a resposta é adequada como voz oficial do hotel? Reprove
         se contiver promessa que o hotel não pode cumprir, opinião pessoal do
         atendente, desabafo, crítica a colega/empresa, linguagem ofensiva ou
         qualquer coisa que não deveria ser dita a outro cliente.

      ## CRITÉRIOS DE FORMA (nota 1 a 5 — NÃO reprovam)

      5. **humanizada** — soa como uma pessoa de verdade falando no WhatsApp, em
         português brasileiro natural? Nota baixa para texto robótico, formal
         demais, cheio de jargão ou com estrutura de documento.

      6. **autocontida** — a pergunta é clara e a resposta se sustenta sozinha,
         sem depender do contexto daquela conversa?

      Se 5 ou 6 tiverem nota baixa, reescreva em `pergunta_revisada` e
      `resposta_revisada`. ATENÇÃO: você só pode mudar a FORMA (redação, tom,
      clareza). Nunca acrescente, remova ou altere informação. Se não houver o
      que melhorar, repita o texto original.

      ## FAQ CANDIDATA

      Pergunta: #{question}
      Resposta: #{answer}

      ## CONHECIMENTO JÁ EXISTENTE NA BASE (para checar contradição)

      #{formatted_neighbours}

      ## CONVERSA DE ORIGEM (para checar fidelidade)

      #{conversation_excerpt}

      ## SAÍDA

      Retorne SOMENTE JSON válido, nada além disso:

      ```json
      {
        "fidelidade": { "aprovado": true, "motivo": "..." },
        "generalizavel": { "aprovado": true, "motivo": "..." },
        "nao_contradiz": { "aprovado": true, "motivo": "..." },
        "politica": { "aprovado": true, "motivo": "..." },
        "humanizada": { "nota": 4, "motivo": "..." },
        "autocontida": { "nota": 5, "motivo": "..." },
        "pergunta_revisada": "...",
        "resposta_revisada": "..."
      }
      ```

      Na dúvida, REPROVE. Conhecimento errado na base contamina todos os
      atendimentos seguintes; uma FAQ a menos só mantém o estado atual.
    PROMPT
  end

  def formatted_neighbours
    return 'Nenhum conhecimento relacionado na base.' if neighbours.blank?

    neighbours.map { |faq| "- P: #{faq.question}\n  R: #{faq.answer}" }.join("\n")
  end

  def conversation_excerpt
    text = conversation&.to_llm_text.to_s
    return 'Conversa indisponível.' if text.blank?

    text.truncate(MAX_CONVERSATION_CHARS)
  rescue StandardError => e
    Rails.logger.warn("[Captain::FaqJudge] conversation excerpt failed: #{e.message}")
    'Conversa indisponível.'
  end
end
