# rubocop:disable Metrics/ClassLength
class Captain::ContactMemories::ExtractionService
  MAX_FACTS = 5
  MIN_CONFIDENCE = 0.5
  EXTRACTION_MODEL = 'gpt-4o-mini'.freeze
  MAX_CHARS = 40_000 # matches Captain::Llm::ConversationInsightService convention
  SCOPE_PATTERN = /\A(global|unit:\d+)\z/

  def initialize(conversation:)
    @conversation = conversation
  end

  def call
    raw = call_llm
    parsed = JSON.parse(raw)
    facts = parsed.fetch('facts', [])
    facts.filter_map { |f| normalize(f) }.take(MAX_FACTS)
  rescue JSON::ParserError => e
    Rails.logger.warn("[ContactMemory::ExtractionService] JSON parse: #{e.message}")
    []
  rescue StandardError => e
    Rails.logger.error("[ContactMemory::ExtractionService] #{e.class}: #{e.message}")
    []
  end

  private

  # TODO(phase-6): add Integrations::LlmInstrumentation wrap for OTEL metrics
  # (extraction_count, extraction_cost, facts_per_call, llm_error_rate).
  def call_llm
    RubyLLM.chat(model: EXTRACTION_MODEL)
           .with_temperature(0)
           .with_params(response_format: { type: 'json_object' })
           .ask(build_prompt)
           .content.to_s
  end

  def build_prompt
    <<~PROMPT
      Você é um analista conservador que extrai apenas FATOS MEMORÁVEIS de uma conversa de WhatsApp entre um hóspede e um hotel. Sua missão é criar memória útil de longo prazo sobre o cliente — não transcrever a conversa.

      ## PRINCÍPIO ZERO — LITERALIDADE SOBRE INFERÊNCIA

      Você extrai o que o cliente DISSE e o que ACONTECEU, não o que você acha que ele quis dizer ou o que provavelmente vai acontecer. Quando em dúvida entre registrar uma interpretação ou não registrar nada: NÃO REGISTRE. Memória errada é muito pior que memória ausente — memória errada contamina conversas futuras e faz o atendente mentir pro cliente.

      ## REGRA DE OURO — AÇÃO CONSUMADA vs INTENÇÃO FUTURA

      **NUNCA** registre como fato uma ação que o cliente apenas EXPRESSOU INTENÇÃO de fazer. Isso é o erro mais grave possível — contamina o recall e faz o bot afirmar falsidades nas próximas conversas.

      ### Exemplo REAL de erro a não repetir:
      - Cliente: "Maravilha, entro em contato amanhã para reservar"
      - Bot: "Fico à disposição pra te ajudar amanhã"
      - ❌ **ERRADO (alucinação)**: `padrao_comportamental` "Reservou Hidromassagem para pernoite em 21/04/2026"
      - ✅ **CERTO**: nada. O cliente não reservou — disse que vai entrar em contato. Se amanhã ele reservar de fato, a conversa de amanhã vira memória.

      ### Sinais de AÇÃO CONSUMADA (pode virar `padrao_comportamental` com data):
      - **Pagamento confirmado**: cliente disse literalmente "paguei o Pix", "Pix pago", "fiz o pagamento", "acabei de pagar", OU aparece mensagem automática "Pagamento confirmado" / "Pix recebido" do bot.
      - Registro de estadia PASSADA: "fiquei na Alexa em 03/02", "nos hospedamos no fim de semana".
      - Cliente disse "já estou no hotel", "cheguei", "fazendo check-in agora".

      ### ATENÇÃO — Pix GERADO ≠ Pix PAGO (diferença crítica, mas registrável)

      Quando o bot gera um Pix e o cliente **só agradece ou silencia**, isso **NÃO é reserva consumada**. Pix gerado é um convite pra pagar — a reserva só vira real quando o pagamento cai. MAS a solicitação em si é um fato útil de registrar, porque é base pra follow-up.

      | Situação na conversa | `padrao_comportamental` aceitável |
      |---|---|
      | Bot gerou Pix + cliente disse "obrigado" / silêncio | ✅ "Solicitou Pix para <suíte> <permanência> em DD/MM/AAAA, aguardando pagamento" |
      | Bot gerou Pix + cliente disse "paguei" / "fiz o Pix" | ✅ "Reservou <suíte> <permanência> em DD/MM/AAAA" |
      | Bot gerou Pix + msg automática "Pagamento confirmado" | ✅ "Reservou <suíte> <permanência> em DD/MM/AAAA" |
      | Cliente só pediu valor sem pedir pra reservar | ❌ NÃO (apenas consulta de preço) |
      | Cliente disse "entro em contato amanhã pra reservar" | ❌ NÃO (intenção futura vazia) |

      Regra de ouro:
      - Se CONFIRMOU pagamento → `"Reservou X para Y em DD/MM/AAAA"` (afirma a reserva como concreta).
      - Se SÓ pediu Pix → `"Solicitou Pix para X <permanência> em DD/MM/AAAA, aguardando pagamento"` (registra a solicitação sem afirmar que fechou). A frase **precisa conter "aguardando pagamento"** ou equivalente, pra deixar claro que é pré-reserva.
      - Se não teve Pix e nem reserva explícita → não extraia nada sobre reserva.

      Isso vale pra `padrao_comportamental` somente. Preferência, data comemorativa, restrição etc seguem as regras próprias de cada tipo.

      ### Sinais de INTENÇÃO FUTURA (NÃO MEMORIZE — retorne nada):
      - "Entro em contato amanhã para reservar"
      - "Vou querer reservar"
      - "Pretendo fazer uma reserva"
      - "Tô pensando em reservar"
      - "Quero ver opções"
      - "Depois eu vejo / me avise depois"
      - "Amanhã eu decido"
      - Qualquer conversa de orçamento/consulta sem fechamento concreto.

      ### Teste antes de registrar ação:
      Releia o último terço da conversa. A reserva foi EFETIVAMENTE fechada (Pix gerado + cliente aceitou, ou cliente disse "pode confirmar" + bot confirmou)? Se não conseguir apontar a virada de "intenção" pra "feito" com trecho literal, NÃO É AÇÃO CONSUMADA — é intenção efêmera e NÃO VIRA memória.

      ## CONTEXTO DO NEGÓCIO (dados canônicos — NÃO invente fora desta lista)

      - **Suítes válidas**: APENAS `Alexa`, `Stilo`, `Hidromassagem`. Se o texto mencionar qualquer outro nome de suíte (ex: "Aluba", "Premium", "Deluxe"), é ERRO de transcrição ou alucinação — DESCARTE o fato. Nunca normalize pra um dos 3 nomes automaticamente: se o cliente disse "queria a Aluba", descarte silenciosamente.
      - **Permanências válidas**: `2hrs`, `3hrs`, `4hrs`, `pernoite`, `diária`. Qualquer outro termo = descarte.

      ## DADOS CADASTRAIS NÃO SÃO MEMÓRIA (regra absoluta)

      Os seguintes dados são armazenados separadamente no perfil do contato e NUNCA devem virar memória:
      - Nome completo / primeiro nome / apelido
      - CPF, RG, passaporte, qualquer documento
      - Email, telefone, endereço
      - Data de nascimento (a não ser que esteja explicitamente vinculada a celebração no hotel — aí vira `data_comemorativa`, não cadastro)

      Exemplos de fatos INVÁLIDOS que NÃO devem ser extraídos:
      - ❌ "Rodrigo tem um CPF que pode ser usado para reservas"
      - ❌ "Cliente forneceu nome e CPF"
      - ❌ "Rodrigo Borba Machado é o nome do cliente"
      - ❌ "O email é x@y.com"
      - ❌ "Informou telefone para contato"

      ## TAXONOMIA ESTRITA

      Use apenas estes 9 tipos. Cada tipo tem definição precisa + exemplos do que SIM e do que NÃO é.

      1. **preferencia** — APENAS se o cliente DECLAROU EXPLICITAMENTE uma preferência com palavras como "prefiro", "gosto mais de", "sempre escolho", "adoro", "minha favorita é". Sem declaração explícita = NÃO É PREFERÊNCIA.
         SIM: "Prefiro sempre a Stilo com hidro"
         SIM: "Gosto de chegar tarde, depois das 22h"
         SIM: "Minha suíte favorita é a Hidromassagem"
         NÃO: "Quero reservar uma suíte" (é pedido pontual, não preferência recorrente)
         NÃO: "Escolheu a Alexa dessa vez" (foi UMA escolha, não preferência declarada — use `padrao_comportamental` com data)
         NÃO: "Reservou Alexa para pernoite" (é uma transação, use `padrao_comportamental` com data)
         REGRA CRÍTICA: nunca extraia "Prefere X" se a única evidência é uma escolha. Preferência precisa de DECLARAÇÃO EXPLÍCITA com as palavras-gatilho acima.

      2. **data_comemorativa** — data anual recorrente declarada pelo cliente (aniversário dele/esposa/casamento, Dia dos Namorados que ele celebra aqui, etc).
         SIM: "É nosso aniversário de casamento dia 14/02"
         SIM: "Aniversário da minha esposa em 3/8"
         NÃO: "Quero reservar dia 20/04" (é data da reserva, não data comemorativa)
         NÃO: "Ontem foi meu aniversário" (só comemora aqui se mencionar que TRADICIONALMENTE vem)

      3. **vinculo_social** — relacionamento social duradouro com outra pessoa mencionada (esposa, marido, filho, amigo, colega).
         SIM: "Sempre venho com minha esposa Mariana"
         SIM: "Indicado pelo Márcio, meu amigo"
         NÃO: "Obrigado" (não é vínculo)
         NÃO: "Expressou gratidão ao hotel" (isso é gentileza, não vínculo social)

      4. **padrao_comportamental** — evento de escolha EFETIVAMENTE CONSUMADA pelo cliente (ver REGRA DE OURO), OU declaração explícita de hábito.
         **TODO fato desse tipo DEVE incluir a data da conversa no content**, no formato:
         "Reservou Stilo para pernoite em 23/05/2026"
         "Escolheu 4hrs em 14/03/2026"
         SIM: "Sempre chego tarde, entre 23h e meia-noite" (declarou hábito)
         SIM: "Costumo ficar só o pernoite" (declarou hábito)
         SIM: "Reservou Alexa para pernoite em 23/05/2026" — APENAS se há confirmação LITERAL de pagamento (cliente disse "paguei"/"Pix pago" OU mensagem automática "Pagamento confirmado"). Pix meramente gerado não conta.
         SIM: "Solicitou Pix para Hidromassagem pernoite em 25/04/2026, aguardando pagamento" — quando o bot gerou Pix mas o cliente ainda não confirmou pagamento. É útil pra follow-up e pra entender interesses.
         SIM: "Escolheu 4hrs na visita de 14/03/2026" — se efetivamente escolheu e fechou
         NÃO: "Costuma ficar 2 horas" (SEM DATA e SEM declaração — banido)
         NÃO: "Prefere permanência de 4 horas" (banido — isso seria preferencia, que exige declaração explícita)
         NÃO: "Vai chegar às 22h hoje" (intenção da conversa atual, não histórico)
         NÃO: "Reservou X" quando o cliente só disse "entro em contato amanhã para reservar" ou "quero reservar" sem Pix gerado (intenção futura vazia).
         NÃO: "Reservou X" quando o bot apenas cotou preço e o cliente não pediu reserva.
         NÃO: "Reservou X em DD/MM" quando o bot GEROU Pix mas NÃO há confirmação de pagamento — use a variante "Solicitou Pix para X ..., aguardando pagamento" nesse caso.
         REGRA CRÍTICA: se você vai registrar uma escolha pontual, (a) especifique se é reserva confirmada (pagamento caiu) ou solicitação em aberto (Pix gerado sem pagamento), e (b) SEMPRE inclua a data no content. "Aguardando pagamento" é obrigatório quando não houve confirmação.

      5. **reclamacao** — queixa EXPLÍCITA sobre algo que desagradou/frustrou/causou problema, com sentimento negativo claro.
         SIM: "O ar-condicionado estava barulhento demais, não dormi direito"
         SIM: "Achei péssimo o atendimento da recepcionista X"
         NÃO: "Tem estacionamento?" (é PERGUNTA, não reclamação)
         NÃO: "Vocês aceitam pet?" (é dúvida)
         NÃO: "Poderia ter chegado mais cedo" (é observação, sem queixa)

      6. **feedback_positivo** — elogio EXPLÍCITO sobre pessoa, serviço ou experiência específica.
         SIM: "A Dona Cida do café é maravilhosa, sempre muito atenciosa"
         SIM: "Foi a melhor estadia que tive, amei a limpeza"
         NÃO: "Obrigado" ou "Agradeceu o atendimento" (cortesia genérica, não elogio memorável)
         NÃO: "Foi incentivado a aproveitar o aniversário" (isso é resposta do atendente, não fala do cliente)

      7. **restricao** — restrição médica, alérgica, dietética ou de mobilidade que afeta hospedagem.
         SIM: "Sou alérgico a amendoim"
         SIM: "Não posso subir escadas, preciso de quarto térreo"
         NÃO: "O hotel não aceita pet" (é regra do hotel, não restrição do cliente)
         NÃO: "Hoje vou comer só frutas" (preferência pontual, não restrição médica)

      8. **vinculo_comercial** — relação comercial/profissional declarada que afeta tratamento (funcionário de empresa parceira, influenciador, agente de viagem, desconto corporativo).
         SIM: "Sou funcionário da Caixa, tenho desconto corp"
         SIM: "Trabalho com turismo, venho avaliar o hotel"
         NÃO: "Fez uma reserva para X" (é reserva, não vínculo comercial)
         NÃO: "Já veio 3 vezes" (frequência não é vínculo comercial)

      9. **contexto_pessoal** — fato pessoal relevante que afeta o atendimento (profissão, local onde mora, situação de vida).
         SIM: "Sou caminhoneiro, viajo sempre, preciso hospedagem rápida"
         SIM: "Moro em Luziânia, venho no fim de semana"
         NÃO: "Me chamo Rodrigo" (nome vai nos dados cadastrais, não é memória)
         NÃO: "Informou CPF e email" (dados cadastrais, não memória)
         NÃO: "Está interessado em reservar" (intenção da conversa, não perfil)

      ## REGRAS ABSOLUTAS (violação = FATO DESCARTADO)

      1. **Evidência OBRIGATÓRIA**: cada fato precisa de um trecho LITERAL da conversa. Se não tem trecho claro, não extraia.
      2. **Perguntas/dúvidas NÃO são reclamação nem memória**: se o cliente fez uma pergunta ("tem X?", "aceita Y?"), isso é informação que ele queria, não fato sobre ele.
      3. **Cortesia genérica NÃO é feedback**: "obrigado", "tá bom", "ok" NÃO viram feedback_positivo.
      4. **Aplicar a REGRA DE OURO de ação-consumada vs intenção-futura**: "informou CPF" nunca é memória (é cadastro). "Reservou X em tal data" SÓ se houve confirmação de pagamento; se o bot só gerou Pix sem pagamento, use o formato "Solicitou Pix para X em DD/MM/AAAA, aguardando pagamento". Cotação de preço pura ou "depois eu decido" = NÃO EXTRAIA. Sempre diferencie ação confirmada (Reservou) de solicitação em aberto (Solicitou Pix...aguardando pagamento).
      5. **Ações do atendente NÃO são memória do cliente**: se o bot "incentivou X" ou "ofereceu Y", isso descreve o atendente, não o cliente. Ignore.
      6. **Máximo 5 fatos por conversa**. Se há dúvida entre extrair ou não, DESCARTE. Qualidade > quantidade.
      7. **Se a conversa não tem NADA realmente memorável**, retorne `{"facts": []}`. Isso é o comportamento normal e esperado da maioria das conversas transacionais.

      ## FORMATO DE SAÍDA

      JSON: `{"facts": [{...}, ...]}` onde cada fato tem:
      - `memory_type`: um dos 9 tipos acima
      - `content`: frase curta em português, 3ª pessoa ("Prefere Stilo com hidro"), max 1000 chars
      - `evidence`: trecho LITERAL da conversa que prova o fato (copiar aspas do cliente)
      - `confidence`: 0.0 a 1.0 (use ≥0.9 só se for totalmente explícito, 0.7-0.89 se for forte inferência, <0.7 descarte)
      - `scope`: `global` na maioria dos casos. Use `unit:<id>` apenas para reclamação/feedback sobre algo específico de UMA unidade.

      ## CONVERSA A ANALISAR

      **Data de referência desta conversa:** #{conversation_reference_date}
      (use essa data em toda memória de escolha do tipo `padrao_comportamental`)

      #{formatted_messages}

      Retorne JSON puro, nada além disso.
    PROMPT
  end

  # Date of the conversation, used as the temporal reference the LLM must embed
  # in padrao_comportamental memories. Falls back to now if somehow no message.
  def conversation_reference_date
    last = @conversation.messages.where(private: false).maximum(:created_at)
    (last || Time.current).strftime('%d/%m/%Y')
  end

  # Feeds the LLM extractor. MUST exclude:
  # - private: true (internal agent-to-agent notes — never seen by the guest; privacy leak if extracted)
  # - failed status (outbound messages that never reached the guest — extracting from them is dishonest)
  def formatted_messages
    scope = @conversation.messages
                         .where(message_type: [:incoming, :outgoing], private: false)
                         .where.not(status: :failed)
                         .order(created_at: :asc)

    limited_messages(scope).map { |m| "[#{m.message_type}] #{m.content}" }.join("\n")
  end

  def limited_messages(scope)
    all = scope.to_a
    return all if all.sum { |m| m.content.to_s.length } <= MAX_CHARS

    # keep most recent messages, drop oldest until under cap
    kept = []
    total = 0
    all.reverse_each do |msg|
      len = msg.content.to_s.length
      break if total + len > MAX_CHARS

      kept.unshift(msg)
      total += len
    end
    kept
  end

  def normalize(raw_fact)
    type = raw_fact['memory_type'].to_s
    content = raw_fact['content'].to_s.strip
    evidence = raw_fact['evidence'].to_s.strip
    confidence = raw_fact['confidence'].to_f
    raw_scope = raw_fact['scope'].to_s.presence || 'global'
    scope = valid_scope?(raw_scope) ? raw_scope : 'global'

    return nil unless Captain::ContactMemory::MEMORY_TYPES.include?(type)
    return nil if content.blank? || evidence.blank?
    return nil if confidence < MIN_CONFIDENCE

    {
      memory_type: type,
      content: content.truncate(1000),
      evidence: evidence,
      confidence: confidence,
      scope: scope
    }
  end

  def valid_scope?(value)
    SCOPE_PATTERN.match?(value)
  end
end
# rubocop:enable Metrics/ClassLength
