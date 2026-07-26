# PLANO — Ciclo de Aprendizado Autônomo do Captain (Fase 1)

> Status: **aguardando aprovação do Rodrigo** (plano congela após aprovado)
> Data: 2026-07-24
> Escopo: Fase 1 — juiz LLM + quarentena `trial` substituindo a aprovação manual de FAQ

## Objetivo

Quando a IA não sabe e faz triagem humana, a resposta do humano é conteúdo validado. Hoje esse conteúdo já vira FAQ candidata (`Captain::AssistantResponse` com status `pending`), mas morre na fila esperando aprovação manual (no Chatwoot e no Sinal — as gerentes não aprovam). A Fase 1 remove o humano do caminho feliz: um **juiz LLM** avalia cada FAQ candidata e, se passar, ela entra em **quarentena (`trial`)** já ativa na busca das atendentes. Humano só vê exceção (reprovadas pelo juiz) e o digest semanal.

## Diagnóstico (resumo do que já existe)

- Captura pronta: `CaptainListener#conversation_resolved` → `Captain::Llm::ConversationFaqService` gera FAQs só de conversas com resposta humana (`first_reply_created_at`), deduplica por embedding (cosine < 0.3) e salva `pending` com `documentable: conversation`.
- Motivo da triagem: gravado em nota privada (`messages.content_attributes.triage_reason`) — só no caminho Hermes.
- Retrieval: 4 caminhos, todos filtram `.approved` (`faq_lookup` V2, `search_documentation`, MCP/Hermes, guardrail do `agent_runner_service`).
- Modelo de ciclo de vida pronto pra copiar: `Captain::ContactMemory` (expires_at, superseded_by_id, AgingJob).
- Pesquisa de mercado: ninguém (Intercom Fin, Decagon, Zendesk) eliminou a aprovação humana — automatizaram draft, teste e ranking. Vamos além, com kill switch e piloto controlado.

## O que será construído (Fase 1)

### 1. Migration — novos estados e metadados
`captain_assistant_responses`:
- Enum ganha `trial: 2` e `retired: 3` (mantém `pending: 0`, `approved: 1`).
- Novas colunas: `trial_until` (datetime), `source` (string: `human_validated` | `document` | `manual`), `judge_verdict` (jsonb: score, critérios, reasoning, modelo, timestamp), `retired_at` (datetime), `retired_reason` (string).
- **Decisão:** NÃO mudar o default do status (hoje `approved`). Criação manual pela UI continua nascendo aprovada (intencional). Em vez disso, todos os caminhos automatizados passam a setar status explícito:
  - `ConversationFaqService` → `pending` (depois juiz decide)
  - `Documents::ResponseBuilderJob` → `approved` explícito + `source: 'document'`
- Scope novo `retrievable` = `approved + trial`. `retired` nunca é deletado (auditoria/reversão), nunca é buscado.

### 2. `Captain::Llm::FaqJudgeService` (novo)
Juiz LLM (modelo ≠ do gerador, configurável via `InstallationConfig`) com rubrica de 6 critérios, saída JSON estruturada gravada em `judge_verdict`:
1. **Fidelidade** — o conteúdo é o que o humano respondeu (só reformatação permitida, nunca conteúdo novo).
2. **Generalizável** — sem PII, sem valor/desconto negociado pontual, sem contexto de um cliente específico.
3. **Não contradiz a base** — checagem RAG contra top-5 vizinhos `retrievable` da mesma assistant.
4. **Política da unidade** — sem promessa proibida, dentro do tom da marca.
5. **Humanizada** — resposta soa natural em pt-BR, não robótica (aula Manual de Donos: cliente perceber robô derruba fechamento em até 80%).
6. **Autocontida** — pergunta clara + resposta completa, funciona fora do contexto original.

Critérios 1–4 são eliminatórios; 5–6 geram edição automática (o juiz pode reescrever formato, nunca conteúdo). Aprovada → `trial` com `trial_until = 30.days.from_now`. Reprovada → permanece `pending` com reasoning gravado (fila de exceção).

### 3. Integração no `ConversationFaqService`
- Após gerar + deduplicar, chama o juiz para cada FAQ única.
- Novo guard: pular conversas auto-resolvidas por inatividade **sem** mensagem de agente humano após o handoff (evita aprender de conversa que morreu sem resposta boa).
- Lê a nota de triagem da conversa e grava `triage_reason` no metadata da FAQ (prioriza o que nasceu de gap real da IA).
- Prompt de extração customizado em pt-BR (hoje é o genérico do upstream em inglês).

### 4. Retrieval — `approved` → `retrievable` nos 4 caminhos
- `enterprise/lib/captain/tools/faq_lookup_tool.rb`
- `enterprise/app/services/captain/tools/search_documentation_service.rb`
- `enterprise/app/services/captain/mcp/tools/faq_lookup_tool.rb` + `search_reply_documentation_service.rb`
- `enterprise/app/services/captain/assistant/agent_runner_service.rb` (guardrail)

### 5. Jobs (sidekiq-cron em `config/schedule.yml`)
- **Promoção diária:** `trial` com `trial_until` vencido e não aposentada/editada → `approved`. (Fase 1 é promoção por tempo; veredito por métrica entra na Fase 2 com attribution.)
- **Digest semanal de aprendizado:** por unidade — quantas aprendidas, em trial, promovidas, reprovadas aguardando humano. Entrega pelo mesmo canal do digest CEO existente (`schedule.yml`, segunda 11:00 UTC).

### 6. Motivo de triagem nos handoffs não-Hermes (pequeno)
`bot_handoff` do motor Captain interno (`response_builder_job`, `agent_runner_service`, `handoff_tool`) passa a gravar nota privada com `triage_reason`, igual ao caminho Hermes — hoje só Hermes grava.

### 7. Rollout controlado
- Feature flag por assistant: `config['feature_faq_auto_judge']` (default off).
- **Piloto: Bianca · H / PrimeAL** (mesma unidade do piloto Sinal), 2 semanas, depois expande.
- Kill switch: desligar a flag volta o comportamento atual (tudo fica `pending`).
- Calibração antes de ligar em produção: 20–30 FAQs candidatas reais rotuladas pelo Rodrigo (aprova/reprova); rake task compara com o juiz; concordância mínima 70% — abaixo disso, ajustar o prompt do juiz, não o gabarito.

## Fora de escopo (fases futuras — NÃO fazer agora)

- **Fase 2:** attribution (qual FAQ trial foi citada em cada resposta), métricas de veredito (re-correção humana, redução de handoff no cluster), veredito por métrica no lugar de promoção por tempo.
- **Fase 3:** substituição Mem0-style (correção nova aposenta e substitui FAQ velha), golden set de regressão, tool MCP de escrita pro Sinal.
- Reforma do módulo Qualidade IA do Sinal (vira observabilidade/override — sem mudança agora; a esteira atual dele continua funcionando em paralelo).
- Captura de objeções/desejos como subproduto ("não desperdice os dados") — já coberto parcialmente por `ConversationInsight` (`faq_gaps`, `ai_failures`); integração fica pra Fase 2.

## Riscos e mitigação

| Risco | Mitigação |
|---|---|
| Juiz aprova FAQ ruim que vai pro ar | Piloto em 1 unidade + trial marcado + digest expõe tudo + kill switch + calibração ≥ 70% antes de ligar |
| Conversa auto-resolvida vira FAQ lixo | Guard novo no `ConversationFaqService` (item 3) |
| Insert sem status entra vivo (default `approved`) | Status explícito em todos os caminhos automatizados (item 1) |
| `Documents::ResponseBuilderJob` faz `destroy_all` ao regerar | FAQs aprendidas ficam com `documentable: Conversation` — nunca amarrar a `Captain::Document` |
| Regressão nos fluxos atuais de FAQ | Suite RSpec cobrindo os 4 caminhos de retrieval + fluxo de documento inalterado |

## Insights incorporados da aula (Manual de Donos #15 — Eduardo Mayer/Vekta)

- **Humanização como critério do juiz** (critério 5) — "cliente perceber robô = queda de até 80% no fechamento".
- **Resumo como artefato de handoff** (padrão Cyborg da Vekta): registrado como candidato de melhoria pra nota de triagem (a nota pode incluir resumo da conversa pro humano responder mais rápido) — entra no item 6 se couber sem crescer escopo, senão Fase 2.
- **"Não desperdice os dados"** — reconhecido, mantido fora de escopo da Fase 1 (ver acima).
- **Validação da dor**: participante relatou "10 meses treinando IA corrigindo erros diários" sem método — exatamente o buraco que este loop fecha. A aula não trouxe mecanismo técnico de melhoria contínua (confirmado na transcrição completa); o desenho técnico vem da pesquisa Intercom/Decagon/Mem0.

## Arquivos que serão tocados

- `db/migrate/*` (nova migration)
- `enterprise/app/models/captain/assistant_response.rb` (enum, scopes, validações)
- `enterprise/app/services/captain/llm/faq_judge_service.rb` (novo)
- `enterprise/app/services/captain/llm/conversation_faq_service.rb`
- `enterprise/app/services/captain/llm/system_prompts_service.rb` (prompt pt-BR)
- 4 caminhos de retrieval (item 4)
- `enterprise/app/jobs/captain/assistant_responses/probation_job.rb` (novo) + digest job (novo)
- `config/schedule.yml`
- `app/controllers/webhooks/captain/hermes_callback_controller.rb` / serviços de handoff não-Hermes (item 6)
- `enterprise/app/jobs/captain/documents/response_builder_job.rb` (status explícito)
- `lib/tasks/captain_judge_calibration.rake` (novo)
- i18n `en` + `pt_BR` (digest e strings de UI se houver)
- Specs correspondentes em `spec/enterprise/`
