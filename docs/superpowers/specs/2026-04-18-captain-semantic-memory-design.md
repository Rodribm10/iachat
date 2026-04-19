# Spec — Memória Semântica Episódica do Cliente (Captain)

**Data:** 2026-04-18
**Branch:** `feat/captain-semantic-memory`
**Épico:** A (memória). Épico B (evolução do orchestrator) será spec separado após este entrar em produção.

---

## 1. Contexto e motivação

Hoje o Captain (agente de WhatsApp da fazer.ai para o Grupo 1001 Noites) tem 3 camadas de memória funcionais:

| Camada | Onde | Natureza |
|---|---|---|
| Identity | `contact.custom_attributes` (cpf, total_reservas, ultima_suite…) | Key-value, determinístico |
| Working memory | últimas N mensagens da conversa (bruto) | Literal, volátil |
| Knowledge | `captain_assistant_responses.embedding` (FAQ) | Semântica (guardrail) |

**Falta a Camada 3 — memória episódica do cliente:** fatos acumulados ao longo do relacionamento (preferências, datas comemorativas, reclamações, padrões). Sem ela, clientes recorrentes são tratados como novos; experiência é genérica; o valor de "grupo que conhece o hóspede" não existe.

**Objetivo:** adicionar Camada 3 ao Captain, sem alterar as outras 3, com memória semântica real (embeddings + cosine + pgvector), fatos extraídos automaticamente ao fim de cada conversa, injetados no contexto do LLM via top-K retrieval.

**Fora de escopo:** refatorar as 3 camadas existentes; trocar gem `agents` por LangChain/LangGraph; outbound proativo (campanhas) — virarão features derivadas após este épico estável.

## 2. Problema concreto que resolvemos

- Cliente volta em 6 meses → agente começa do zero, pede dados de novo.
- Cliente mencionou preferência por Stilo com hidro 5x → agente nunca oferece proativamente.
- Cliente reclamou de ar-condicionado → na próxima reserva, agente não sabe evitar a mesma suíte.
- Cliente passa em Prime Ceilândia, depois Prime Águas Lindas → agente da 2ª unidade não sabe quem é.
- Grupo não consegue gerar relatórios de *"top reclamações por unidade nos últimos 90 dias"* porque esse dado não está estruturado.

## 3. Decisões tomadas no brainstorming

| # | Decisão | Valor |
|---|---|---|
| 1 | **Quando extrair** | Ao resolver conversa OU após silêncio > 30min |
| 2 | **Validação** | 100% automático com salvaguardas (evidence obrigatória, confidence ≥ 0.5). Alternativas B/C/D documentadas como plano de contingência |
| 3 | **Scope** | Global no recall (experiência unificada no grupo), atribuição por unidade no registro (`source_unit_id` pra relatórios) |
| 4 | **Taxonomia** | 9 tipos fixos iniciais (ver §5) |
| 5 | **Limites** | Até 5 fatos por conversa, até 50 ativos por contato (LRU ao atingir) |
| 6 | **Envelhecimento** | TTL por tipo, soft-delete após expirar, redução de peso no recall antes de deletar |
| 7 | **Conflitos** | Supersedência automática via checker de contradição semântica + lexical |
| 8 | **LGPD** | Soft-delete 30d → hard-delete via cron diário. Botão "esquecer tudo" no painel |
| 9 | **Feature flags** | `extraction_enabled` e `recall_enabled` independentes, por account, default OFF |
| 10 | **Decomposição** | Épico A (este) e Épico B (evolução orchestrator) serão sequenciais, sem esperar 30 dias entre um e outro |

## 4. Arquitetura — 4 camadas integradas em runtime

```
mensagem entra
  │
  ▼
┌─────────────────┐   key-value, ~1ms, determinístico
│ 1. IDENTITY     │ ← contact.custom_attributes (hoje, inalterado)
└─────────────────┘
  │
  ▼
┌─────────────────┐   literal, ~5ms, volátil
│ 2. WORKING MEM  │ ← últimas N mensagens brutas (hoje, inalterado)
└─────────────────┘
  │
  ▼
┌─────────────────┐   semântica, ~100-200ms, top-5 ← NOVO
│ 3. EPISODIC     │ ← captain_contact_memories por cosine
└─────────────────┘
  │
  ▼
┌─────────────────┐   semântica (guardrail pós-geração)
│ 4. KNOWLEDGE    │ ← captain_assistant_responses (hoje, inalterado)
└─────────────────┘
  │
  ▼
LLM responde
```

Camadas 1 e 2 rodam antes do LLM; Camada 3 também (novo); Camada 4 roda depois como guardrail. Só a Camada 3 é adicionada — nenhuma outra é modificada.

## 5. Taxonomia dos fatos — 9 tipos iniciais

| `memory_type` | Exemplo | Scope default | TTL | Ao expirar |
|---|---|---|---|---|
| `preferencia` | "Prefere Stilo com hidromassagem" | global | 365d | Reduz peso no recall (×0.7), não deleta |
| `data_comemorativa` | "Aniversário casamento 14/02" | global | Nunca | — |
| `vinculo_social` | "Vem com esposa Mariana" | global | 730d | Deleta |
| `padrao_comportamental` | "Chega entre 21h-22h" | unit | 365d | Reduz peso |
| `reclamacao` | "Ar-condicionado da 204 barulhento em mar/26" | unit | 180d | Deleta |
| `feedback_positivo` | "Elogiou a Dona Cida do café" | unit | 365d | Deleta |
| `restricao` | "Alérgico a amendoim" | global | Nunca | — |
| `vinculo_comercial` | "Funcionário Caixa, desconto corp" | global | 365d | Reduz peso |
| `contexto_pessoal` | "Trabalha viajando, hospedagem rápida" | global | 365d | Reduz peso |

Tipos novos podem ser adicionados depois sem migration (campo string no schema).

## 6. Modelo de dados

### 6.1 Tabela `captain_contact_memories`

```sql
CREATE TABLE captain_contact_memories (
  id                      BIGSERIAL PRIMARY KEY,
  account_id              BIGINT NOT NULL REFERENCES accounts(id),
  contact_id              BIGINT NOT NULL REFERENCES contacts(id),
  memory_type             VARCHAR NOT NULL,
  content                 TEXT NOT NULL,
  evidence                TEXT NOT NULL,
  confidence              FLOAT NOT NULL,
  scope                   VARCHAR NOT NULL DEFAULT 'global',
  embedding               vector(1536),
  source_conversation_id  BIGINT REFERENCES conversations(id),
  source_unit_id          BIGINT REFERENCES captain_units(id),
  source_inbox_id         BIGINT REFERENCES inboxes(id),
  expires_at              TIMESTAMP,
  last_verified_at        TIMESTAMP NOT NULL,
  superseded_at           TIMESTAMP,
  superseded_by_id        BIGINT REFERENCES captain_contact_memories(id),
  deleted_at              TIMESTAMP,
  metadata                JSONB NOT NULL DEFAULT '{}',
  created_at              TIMESTAMP NOT NULL,
  updated_at              TIMESTAMP NOT NULL
);
```

### 6.2 Índices

```sql
CREATE INDEX idx_ccm_recall ON captain_contact_memories (account_id, contact_id)
  WHERE deleted_at IS NULL AND superseded_at IS NULL;

CREATE INDEX idx_ccm_embedding ON captain_contact_memories
  USING ivfflat (embedding vector_cosine_ops) WITH (lists = 100);

CREATE INDEX idx_ccm_analytics ON captain_contact_memories
  (source_unit_id, memory_type, created_at);

CREATE INDEX idx_ccm_hard_delete ON captain_contact_memories (deleted_at)
  WHERE deleted_at IS NOT NULL;

CREATE INDEX idx_ccm_superseded ON captain_contact_memories (superseded_by_id)
  WHERE superseded_at IS NOT NULL;
```

### 6.3 Validações no model

- `memory_type` ∈ enum dos 9 tipos.
- `evidence` presence (garantia anti-hallucination — fato sem trecho literal = rejeitado no extractor).
- `confidence` entre 0 e 1.
- `content` non-empty, max 1000 chars (fatos devem ser concisos).

## 7. Componentes (arquivos novos)

### 7.1 Model

**`enterprise/app/models/captain/contact_memory.rb`**
- `has_neighbors :embedding` (gem `neighbor`)
- Enum `memory_type` com os 9 valores
- Scopes:
  - `.active` — `WHERE deleted_at IS NULL AND superseded_at IS NULL AND (expires_at IS NULL OR expires_at > NOW())`
  - `.for_contact(id)`, `.by_type(t)`, `.scope_compatible(unit_id)`
- Instance methods:
  - `soft_delete!` — seta `deleted_at = now`
  - `supersede_by!(other)` — seta `superseded_at`, `superseded_by_id`
  - `recall_weight` — retorna 1.0 ou 0.7 (reduz peso se expired)
- Callbacks:
  - `after_commit on: [:create, :update] if saved_change_to_content?` → enfileira `UpdateEmbeddingJob`
  - `after_create_commit` → enfileira `ContradictionCheckerJob`

### 7.2 Services

**`enterprise/app/services/captain/contact_memories/extraction_service.rb`**
- `initialize(conversation:)`
- `#call` → retorna array de hashes dos fatos válidos. NÃO persiste (separação).
- Monta prompt incluindo: histórico completo da conversa, taxonomia dos 9 tipos, exemplos de evidence bem-feito, JSON schema esperado.
- LLM: `gpt-4o-mini`, JSON mode, temperature 0.
- Valida cada fato retornado: `type` válido, `evidence` non-empty, `confidence` ≥ 0.5, `content` dentro do limite.
- Descarta silenciosamente os inválidos. Retorna no máximo 5.

**`enterprise/app/services/captain/contact_memories/recall_service.rb`**
- `initialize(contact:, query_text:, unit_id: nil)`
- `#call` → retorna array ordenado de top-K memories (default K=5).
- Gera embedding da query.
- `Captain::ContactMemory.active.for_contact(contact.id).scope_compatible(unit_id).nearest_neighbors(:embedding, embedding, distance: 'cosine').limit(K)`.
- Aplica `recall_weight` ao cosine score final.
- Timeout de 500ms via `Timeout::timeout`. Em caso de erro ou timeout, retorna `[]`.

**`enterprise/app/services/captain/contact_memories/contradiction_checker_service.rb`**
- `initialize(memory:)`
- `#call` → marca fatos anteriores como `superseded_by` se detectar contradição.
- Busca candidatos: `active.for_contact.by_type(memory.memory_type).where.not(id: memory.id).where('embedding <=> ? < 0.6', memory.embedding)`.
- Para cada candidato (max 3), chama LLM barato (gpt-4o-mini, 1 pergunta binária): *"Esses 2 fatos se contradizem? sim/não"*.
- Se "sim": `candidate.supersede_by!(memory)`.

**`enterprise/app/services/captain/contact_memories/prompt_injection_service.rb`**
- `initialize(memories:)`
- `#call` → retorna string XML formatada pra injetar no system prompt.
- Formato:
  ```xml
  <memoria_cliente>
    <preferencia confidence="0.92">Prefere Stilo com hidromassagem</preferencia>
    <data_comemorativa>Aniversário casamento 14/02</data_comemorativa>
  </memoria_cliente>
  ```
- Se `memories.empty?` → retorna string vazia.

### 7.3 Jobs

**`enterprise/app/jobs/captain/contact_memories/extract_from_conversation_job.rb`**
- Argumentos: `conversation_id`.
- Passos:
  1. Checa feature flag `captain_contact_memory_extraction_enabled` na account. Se OFF, early return.
  2. Carrega conversation.
  3. Chama `ExtractionService`.
  4. Persiste os fatos válidos com `source_conversation_id`, `source_unit_id` (vem de `conversation.captain_unit_id` ou inferido via inbox), `source_inbox_id`.
  5. Cada fato criado aciona `UpdateEmbeddingJob` via `after_commit`.
- Idempotência: se já existe `ContactMemory` com o mesmo `source_conversation_id`, skip (não re-extrai).

**`enterprise/app/jobs/captain/contact_memories/update_embedding_job.rb`**
- Argumento: `memory_id`.
- Gera embedding via `RubyLLM.embed(content, model: 'text-embedding-3-small')`.
- Salva `embedding`.
- Retry 3x, backoff exponencial. Se todas falharem, deixa `embedding = NULL` (fato fica invisível no recall).

**`enterprise/app/jobs/captain/contact_memories/contradiction_checker_job.rb`**
- Argumento: `memory_id`.
- Chama `ContradictionCheckerService`.
- Roda APÓS `update_embedding_job` concluir (encadeado).

**`enterprise/app/jobs/captain/contact_memories/silence_detector_job.rb`**
- Cron a cada 10 min (Sidekiq-Cron).
- Busca conversas ativas cuja última mensagem foi há mais de 30 minutos E que ainda não têm `ContactMemory` com `source_conversation_id` igual.
- Enfileira `ExtractFromConversationJob` pra cada uma.

**`enterprise/app/jobs/captain/contact_memories/aging_job.rb`**
- Cron semanal (domingo madrugada).
- Itera tipos com TTL:
  - Para tipos com "Deleta": `WHERE expires_at < NOW() AND deleted_at IS NULL` → soft-delete.
  - Para tipos com "Reduz peso": marca `expires_at` no futuro (recall já aplica ×0.7 baseado em `expires_at < NOW()`).
- Aplica limite macio de 50 fatos ativos por contato: LRU por `last_verified_at` → soft-delete excedente.

**`enterprise/app/jobs/captain/contact_memories/hard_delete_expired_job.rb`**
- Cron diário.
- `WHERE deleted_at < 30.days.ago` → `DELETE`.
- Loga count por account.

### 7.4 Integração no `AgentRunnerService` (arquivo existente — alteração)

**`enterprise/app/services/captain/assistant/agent_runner_service.rb`**

Alteração mínima, antes do `Agents::Runner.with_agents(...).run(message, ...)`:

```ruby
if account.captain_contact_memory_recall_enabled?
  memories = Captain::ContactMemories::RecallService.new(
    contact: @conversation.contact,
    query_text: message,
    unit_id: @conversation.captain_unit_id
  ).call

  memory_block = Captain::ContactMemories::PromptInjectionService.new(
    memories: memories
  ).call

  system_prompt_with_memory = [system_prompt, memory_block].compact_blank.join("\n\n")
else
  system_prompt_with_memory = system_prompt
end
```

System prompt do orchestrator (Jasmine) e de cada scenario (Daniela etc) passam a receber `system_prompt_with_memory`.

Instrução adicionada ao system prompt base: *"Se houver bloco <memoria_cliente>, use apenas se for natural na conversa. Nunca mencione 'memória', 'registro' ou 'lembrei'. Aja como quem já conhece o cliente."*

### 7.5 Controllers e UI

**`enterprise/app/controllers/api/v1/accounts/contacts/memories_controller.rb`**

```
GET    /api/v1/accounts/:aid/contacts/:cid/memories          # list
PATCH  /api/v1/accounts/:aid/contacts/:cid/memories/:id      # edit content
DELETE /api/v1/accounts/:aid/contacts/:cid/memories/:id      # soft delete
DELETE /api/v1/accounts/:aid/contacts/:cid/memories          # forget all (LGPD)
```

Autorização via Pundit: `ContactMemoryPolicy` — só agentes da account, com permissão de edição de contato.

**UI:** nova tab "Memória" no detalhe do contato. Componente Vue:

`app/javascript/dashboard/routes/dashboard/contact/components/ContactMemories.vue`
- Tabs: "Ativas" | "Histórico" (supersedidas/expiradas)
- Lista: type badge, content, confidence bar, idade, origem (link pra conversa)
- Ações por fato: "editar" (inline), "esquecer"
- Botão master: "Esquecer tudo deste contato" (modal de confirmação com texto livre)

**Configurações do Captain** (página existente): nova seção "Memória do Cliente" com 2 toggles:
- "Aprender com conversas (extraction)"
- "Usar memória nas respostas (recall)"

Cada toggle mostra: status, data da última mudança, quem mudou, custo acumulado do mês (se extraction).

### 7.6 Migrations

- `db/migrate/<ts>_create_captain_contact_memories.rb` — tabela + índices.
- Feature flags via `InstallationConfig` seed (padrão já existe no projeto) — NÃO é migration. Adiciona entries `captain_contact_memory_extraction_enabled` (default false) e `captain_contact_memory_recall_enabled` (default false).

## 8. Data flows

### 8.1 Fluxo de aprendizado (assíncrono)

```
conversation.resolved (Wisper event)   OU   silence_detector_job (cron 10min)
  │
  ▼
ExtractFromConversationJob (Sidekiq, fila captain_heavy)
  │
  ├── feature flag extraction_enabled OFF? → early return
  │
  ▼
ExtractionService
  │   prompt estruturado + histórico
  │   LLM gpt-4o-mini, JSON mode, temp 0
  │   valida evidence + confidence + tipo
  │   retorna até 5 fatos válidos
  ▼
Captain::ContactMemory.create! (N vezes)
  │
  ▼ after_commit
UpdateEmbeddingJob (Sidekiq, fila captain_embeddings)
  │   text-embedding-3-small
  │   retry 3x backoff exp
  ▼ after embedding salvo
ContradictionCheckerJob (Sidekiq, fila captain_heavy)
  │   busca candidatos cosine ≥ 0.6 mesmo tipo/contato
  │   LLM binário por candidato
  │   supersede os contraditórios
```

### 8.2 Fluxo de resposta (síncrono, caminho crítico)

```
message recebida → ResponseBuilderJob (já existe)
  │
  ▼
AgentRunnerService.call (alterado)
  │
  ├── feature flag recall_enabled OFF? → pula recall
  │
  ▼
RecallService.call
  │   embedding da query
  │   nearest_neighbors top-5 com filtro scope
  │   timeout 500ms
  ▼
PromptInjectionService.call
  │   monta bloco XML
  ▼
system_prompt += memory_block
  │
  ▼
Agents::Runner.run (fluxo existente, inalterado)
```

## 9. Error handling

| Falha | Comportamento | Impacto no cliente |
|---|---|---|
| LLM extraction falha (timeout/rate limit) | Retry Sidekiq padrão (3x backoff), depois desiste, loga error | Zero — aprende da próxima conversa |
| LLM retorna JSON inválido | Parse tenta repair (regex simples), se falhar descarta conversa, loga warning | Zero |
| Embedding API falha | Retry 3x, depois deixa `embedding = NULL` | Fato existe mas invisível no recall até próximo update |
| Recall service excede 500ms | Retorna `[]`, loga warning com p99 | Agente responde sem memória dessa vez |
| Recall service lança erro | `rescue StandardError => e; log; return []` | Zero — degradação graciosa |
| Contradição ambígua (>1 candidato alto) | Mantém novo, marca antigos como superseded | Zero |
| Feature flag OFF em runtime | Short-circuit no início | Zero |
| Conversation sem unit_id | `source_unit_id = NULL` — fato fica global | Zero |
| Contact tem 50+ fatos ativos | Aging job aplica LRU na próxima execução semanal | Zero |

**Princípio invariante:** Camada 3 NUNCA bloqueia resposta do agente. Qualquer falha degrada para o comportamento atual (Camadas 1+2+4).

## 10. LGPD e privacidade

- **Soft-delete** por 30 dias permite desfazer exclusão acidental.
- **Hard-delete** automático após 30 dias via cron.
- **Botão "Esquecer tudo"** faz soft-delete em massa de todos os fatos do contato.
- **Transparência:** cliente pode pedir ao agente *"o que vocês sabem sobre mim?"* → tool nova `list_my_memories` (fora do escopo deste épico, mas arquitetura permite).
- **Auditoria:** toda mudança manual (edit, delete) loga `changed_by_user_id` + `changed_at` em `metadata`.
- **Retenção:** fatos sem interação em 365+ dias expiram conforme TTL da tabela.

## 11. Testes

### 11.1 Model specs
- Validações: memory_type enum, evidence presence, confidence range, content length.
- Scopes: active, by_type, scope_compatible.
- Soft-delete e supersede methods.
- has_neighbors busca funcional com fixtures.

### 11.2 Service specs
- **ExtractionService** com 10+ fixtures de conversas reais (sanitizadas) cobrindo: conversa curta, longa, sem fatos, multi-tipo, com alucinação induzida (verificar que descarta).
- **RecallService** com base pre-populada: ordering por cosine correto, scope filter correto, timeout respeitado.
- **ContradictionCheckerService** com pares: idênticos, contraditórios, relacionados mas não contraditórios.
- **PromptInjectionService** formato XML, vazio quando sem fatos.

### 11.3 Job specs
- Idempotência: rodar 2x a mesma `conversation_id` não duplica fatos.
- SilenceDetector detecta corretamente conversas elegíveis e ignora não-elegíveis.
- AgingJob aplica TTL correto por tipo.
- HardDeleteExpired só apaga > 30d.

### 11.4 Integration specs
- `ResponseBuilderJob` com recall ON vs OFF → apenas o ON injeta bloco `<memoria_cliente>` no prompt.
- End-to-end: conversa resolved → fato aprendido → próxima mensagem do mesmo contato usa fato no recall.
- Feature flags: extraction OFF não chama LLM (asserção de mock).

### 11.5 LGPD specs
- `forget_all_memories!` faz soft-delete em todos os fatos do contato.
- Cron hard-delete remove registros > 30d.

## 12. Feature flags e rollout

**Flags (InstallationConfig):**
- `captain_contact_memory_extraction_enabled` — default `false`
- `captain_contact_memory_recall_enabled` — default `false`

**Rollout sugerido:**
1. Deploy com flags OFF — nada muda em produção.
2. Account piloto (Prime Águas Lindas): liga `extraction`. Observa 1 semana: custo real, qualidade dos fatos, erros.
3. Se ok, liga `recall` na mesma piloto. Observa 1 semana: latência P99 agente, reação dos clientes.
4. Expande pras outras 3 marcas em ondas de 48h cada.
5. Se qualquer sinal ruim (custo > previsto, reclamação, latência) → desliga só a flag problemática.

## 13. Observabilidade

**Métricas (Prometheus/OTEL, padrão do projeto):**
- `captain_memory_extraction_count` (counter, por account, por tipo)
- `captain_memory_extraction_cost_brl` (counter, por account)
- `captain_memory_extraction_latency_seconds` (histogram)
- `captain_memory_recall_hit_rate` (gauge — % de mensagens onde recall retornou ≥1 fato)
- `captain_memory_recall_latency_seconds` (histogram, p50/p95/p99)
- `captain_memory_active_facts_count` (gauge, por account)
- `captain_memory_supersedence_count` (counter, por tipo)

**Logs estruturados:**
- Cada extração: conversation_id, fatos extraídos (tipo + confidence), descartados (com razão).
- Cada recall: contact_id, query length, top-5 hits com score, tempo total.
- Cada supersedência: old_id, new_id, reason.

**Dashboard admin:** uma view no Chatwoot admin com custo mensal por account, fatos por tipo, latência P99, taxa de supersedência.

## 14. Custos estimados

Baseado em ~3.000 conversas resolvidas/mês no grupo todo:

| Item | Volume | Custo unit | Total/mês |
|---|---|---|---|
| Extração LLM (gpt-4o-mini) | ~3.000 | R$ 0,015 | **R$ 45,00** |
| Embedding (text-embedding-3-small) | ~15.000 | R$ 0,00005 | **R$ 0,75** |
| Recall embedding (1/msg) | ~20.000 | R$ 0,00005 | **R$ 1,00** |
| Checagem contradição | ~200 | R$ 0,001 | **R$ 0,20** |
| Storage pgvector | 150k fatos em 1 ano | — | R$ 0 |
| **Total estimado** | | | **~R$ 47/mês** |

Feature flag `extraction_enabled` OFF zera 95% do custo. `recall_enabled` OFF zera ~4%.

## 15. Roadmap de features derivadas (documentado, fora deste épico)

**Prioridade alta — atacar após este épico estável ≥ 30 dias em produção:**

- **Outbound proativo por `data_comemorativa`** — cron diário varre fatos com data nos próximos 7 dias, dispara template de proposta personalizada cruzando `preferencia`. Vira canal de vendas passivo.
- **Relatórios por unidade** — página admin com filtros de `source_unit_id` + `memory_type`. Top reclamações, top elogios, perfil do cliente por unidade.
- **Tool `list_my_memories`** no agente pra atender direito de transparência LGPD via WhatsApp.

**Prioridade média — avaliar a partir de dados do épico A:**

- **Épico B — Evolução do orchestrator:** LangGraph via microserviço Python com checkpoints persistidos, retomada exata de conversas longas, paralelismo de tools. Será spec separado. Pode ou não acontecer — depende se a memória já resolve a dor percebida.

**Prioridade baixa — observar antes:**

- Reclassificação manual de fatos (operador reclassifica tipo).
- Import de fatos de outras fontes (CRM, reservas Plug-Play).
- Multi-idioma (hoje assume pt-BR).

## 16. Riscos e mitigações

| Risco | Probabilidade | Impacto | Mitigação |
|---|---|---|---|
| LLM alucinar fatos (inventar coisas) | Média | Alto | Evidence obrigatória + confidence ≥ 0.5 + alternativas B/C/D prontas pra ativar |
| Custo explodir | Baixa | Médio | Flag extraction_enabled desliga 95% do custo |
| Latência do recall piorar resposta | Baixa | Médio | Timeout 500ms com fallback vazio |
| Fatos obsoletos/conflitantes poluírem | Média | Médio | Supersedência automática + aging + limite 50 |
| Vazamento de info entre unidades | Baixa | Alto (LGPD/reputação) | Scope field per-fato pra isolar quando sensível |
| Operador confuso pela nova UI | Baixa | Baixo | Docs + toggle começa OFF, rollout gradual |
| Regressão nas Camadas 1/2/4 | Muito baixa | Alto | Princípio: Camada 3 nunca bloqueia. Todas as alterações são aditivas. |

## 17. Próximos passos

1. **Revisão do spec** (user) — ajustes inline se necessário.
2. **Invocar `writing-plans`** — gera plano executável multi-step com tarefas, ordem, owners, critérios de aceitação.
3. **Execução** — via `executing-plans` ou subagent-driven-development, conforme preferência.
4. **Deploy com flags OFF** → **piloto gradual** → **rollout completo**.
5. **Observar 30 dias** em produção com memória ativa em todas as contas.
6. **Abrir Épico B** com dados reais como input do brainstorming.
