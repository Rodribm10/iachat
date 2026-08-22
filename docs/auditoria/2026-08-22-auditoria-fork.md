# Auditoria do fork iachat — 22/08/2026

Repositório: `Rodribm10/iachat` (fork de `fazer-ai/chatwoot`)
Base de comparação: `fazer-ai/main` @ `cfb204728`
Estado auditado: `origin/main` @ `1f4585125`

Objetivo: entender o que ainda é usado no contexto atual (Hermes como cérebro, não o Captain
interno), o que virou peso morto, o que prende o app ao domínio de hotel e o que precisa mudar
pra abrir uma conta de outro ramo (academia).

> Tudo que depende do estado do banco de produção está marcado como tal e **não** foi assumido.

## Números

| Métrica | Valor |
|---|---|
| Commits do upstream que o fork não tem | 1.102 |
| Versão base do Chatwoot (fork / upstream) | 4.11.0 / 4.17.0 |
| Commits próprios desde 25/02/2026 | 336 |
| Arquivos que só existem no fork | 642 |
| Tabelas exclusivas do fork | 46 |
| Tabelas do upstream que faltam no fork | 29 |

## 1. Arquitetura de hoje

`Enterprise::MessageTemplates::HookExecutionService` decide o motor de resposta:

- `assistant.engine == 'hermes'` → `Captain::Hermes::OutgoingJob` → Hermes responde e chama de volta
- caso contrário → `Captain::Conversation::ResponseBuilderJob` → Captain interno com LLM próprio

O que sustenta o Hermes é o **servidor MCP** (`enterprise/app/services/captain/mcp/`, 19 tools
registradas). O Captain interno arrasta junto o agent runner, o chat LLM, o cliente Codex
(OAuth do ChatGPT Plus) e um cron de 30 em 30 minutos renovando token.

**Pergunta que decide metade da faxina:** existe algum `Captain::Assistant` em produção com
`engine = 'captain_interno'`? Se não, todo o segundo motor é removível.

## 2. Morto confirmado

Verificado no código: sem rota, sem chamador, sem import.

### Subsistema Jasmine inteiro

- `JasmineConfiguration.vue` — nunca importado
- `JasmineKnowledgeBase.vue` — só usado pelo órfão acima
- `api/inbox/jasmine.js` — 12 endpoints, zero rotas no backend (`grep jasmine config/routes.rb` → nada)
- tabelas sem model: `jasmine_collections`, `jasmine_documents`, `jasmine_document_chunks`,
  `jasmine_inbox_collections`, `jasmine_inbox_settings`, `jasmine_tool_configs`
- ~838 linhas de frontend + i18n en/pt_BR

### Camada de tools legada do Captain (duplicada pelo MCP)

Zero referências fora de si e dos specs:

```
Captain::ToolRegistryService
Captain::Tools::BaseService
Captain::Tools::CheckPixPaymentTool
Captain::Tools::CreateReservationIntentTool
Captain::Tools::GenerateReservationLinkTool
Captain::Tools::GenerateRoletaLinkTool
Captain::Tools::GetReservaPrecoTool
Captain::Tools::SendSuiteImagesTool
```

Exceção: `Captain::Tools::GeneratePixTool` ainda é usada por
`Public::Api::V1::Captain::PublicReservationsController` — essa fica.

### 16 tabelas sem model e sem nenhuma citação em código

```
captain_prompt_blocks          captain_prompt_versions
captain_prompt_block_versions  captain_prompt_profiles
captain_prompt_audit_events    captain_prompt_improvement_cases
captain_suites                 captain_assets
captain_extras                 captain_configurations
conversation_crm_insights      frequent_questions
whatsapp_campaigns             whatsapp_campaign_hits
jasmine_documents              jasmine_document_chunks
```

Destaque: a família `captain_prompt_*` é um sistema inteiro de versionamento de prompt com
auditoria e histórico do qual não sobrou nenhum Ruby. `captain_suites` tem FK vinda de
`captain_assets` e não existe `Captain::Suite` no app.

Antes do `drop_table`, checar se há linha em produção.

### Classes soltas sem ponto de entrada

```
Api::V1::…::Reports::ExecutiveController         sem rota (113 linhas)
Captain::Reports::DailySnapshotJob                sem cron, sem chamador
Captain::Inter::WebhookSetupService               sem chamador
Captain::Notifications::SendNotificationService   sem chamador
Whatsapp::MessageDedupLock                        sem chamador
Whatsapp::Providers::EvolutionApi::PayloadParser  sem chamador
settings/captain/units/TestIndex.vue              órfão (29 linhas)
chatwoot_zero/                                    2 PNGs de uma cópia velha
```

### Higiene: `.env.example`

Credenciais de ferramenta de desenvolvimento documentadas como se fossem config do app:
`CLICKUP_API_KEY`, `RAILWAY_TOKEN`, `VERCEL_TOKEN`, `GITHUB_TOKEN`, `N8N_API_KEY`,
`N8N_WEBHOOK_URL`, `AIOS_VERSION`, `CONTEXT7_API_KEY`, `EXA_API_KEY`, `DEEPSEEK_API_KEY`,
`OPENROUTER_API_KEY`.

## 3. Provavelmente morto — só o banco confirma

Está ligado e roda. A pergunta é se alguém usa.

| Subsistema | O que roda hoje | Como confirmar |
|---|---|---|
| Captain interno + Codex | cron a cada 30 min renovando OAuth | assistant com `engine='captain_interno'`? |
| Roleta | cron a cada 5 min + 3 services + página | draw registrado nos últimos 90 dias? |
| Lifecycle / concierge | dispatcher + 6 guards + 3 tabelas | `captain_lifecycle_deliveries` tem linha recente? |
| Retenção / churn outreach | 2 crons (horário + diário 3h) | conversa gerada por churn outreach? |
| CEO Digest + insights semanais | 3 crons semanais → Mattermost | o Mattermost recebe? você lê? |
| Landing hosts + lead clicks | cron horário sincronizando promoções | landing host cadastrado e ativo? |
| Memórias de contato | 4 crons + embeddings + hard delete LGPD | entram no prompt do Hermes? |
| Providers de WhatsApp | 7 no enum: `default`, `whatsapp_cloud`, `wuzapi`, `baileys`, `zapi`, `evolution`, `gowa` | quais têm inbox viva? |

## 4. Acoplamento com hotel

**A arquitetura multi-tenant está limpa.** Nenhum `account_id`/`inbox_id` chumbado no código;
`Captain::Unit` já é `belongs_to :account`. Conta nova é conta nova.

O problema é **vocabulário** — o domínio virou nome de classe, tabela, tool e rótulo de tela.

| Conceito | Serve academia? | Leitura |
|---|---|---|
| `Captain::Unit` | sim | unidade/filial é universal |
| `Captain::Brand` | sim | marca é universal |
| `Captain::PixCharge` + Inter | sim | cobrança é universal, muda o produto |
| suíte (via `captain_gallery_items`) | não | vira produto/serviço genérico |
| `Captain::Reservation` | parcial | academia agenda aula/avaliação — mesmo osso, outro nome |
| Roleta | não | promoção de motel — desligar por conta |
| tools MCP `check_suite_availability`, `send_suite_images`, `reschedule_reservation` | não | registry é global |
| `RESERVA_1001_*` | não | integração de um cliente virou variável global |
| i18n `captain.json` | não | 39 chaves com suíte/reserva/pernoite na tela |

**Ponto mais concreto:** `Captain::Mcp::ToolRegistry::TOOLS` é uma lista fixa e global — toda
tool fica visível pra todo profile do Hermes. A academia vai receber `check_suite_availability`
no `tools/list` dela. Filtrar o registry por conta (ou por capability declarada na unidade) é a
mudança de maior retorno pra abrir o app pra outro ramo.

## 5. Dívida estrutural: 1.102 commits atrás

O fork saiu do upstream em 25/02/2026 e nunca sincronizou. São 29 tabelas de funcionalidade que
existem lá e não aqui:

- **Chat interno** entre agentes (13 tabelas: enquete, reação, anexo, canal, rascunho)
- **Chamadas de voz** (`calls`)
- **Assinatura por inbox**, **pin de conversa**, **desfecho de conversa** (`conversation_outcomes`)
- **Mensagens recorrentes agendadas**, `campaign_recipients`
- **`captain_faq_suggestions` / `captain_faq_observations`** — o ciclo de aprendizado que você
  reimplementou do zero
- **`reporting_events_rollups`** — relatório rápido em base grande
- `data_import_*`, `agent_sessions`, `user_sessions`, `platform_banners`, `group_members`

A branch `archive/rejected-fazer-ai-v4.13.0-64` é a prova de que já houve uma tentativa de sync
rejeitada. Cada mês parado aumenta o custo do merge.

## 6. Ordem de execução

1. **Confirmar o que está vivo em produção** — consultas no banco respondendo a tabela da seção 3.
   Sem isso, toda remoção é aposta.
2. **Remover o morto confirmado** — Jasmine, tools legadas, classes órfãs, `chatwoot_zero/`,
   limpeza do `.env.example`, migration derrubando as 16 tabelas órfãs.
3. **Escopar o registry MCP por conta** — tool declara vertical/capability; registry filtra pelo
   contexto. Pré-requisito real da academia e encolhe o prompt de cada agente.
4. **Abrir a conta da academia** — conta, unidade, assistant com `engine='hermes'`, subscription
   própria. O Construtor (`HermesBuilder`) já existe pra criar agente por conversa; usar como
   caminho oficial em vez de seed de prompt na mão.
5. **Desligar o Captain interno**, se o passo 1 confirmar — sai agent runner, chat LLM, cliente
   Codex e cron de 30 min. Um único caminho de resposta no sistema.
6. **Encarar o sync com o upstream** — com o fork enxuto o merge fica viável. Decidir antes o que
   abandonar da implementação própria em favor do que o upstream já resolveu (o ciclo de FAQ é o
   candidato óbvio).

## 7. Melhorias que a estrutura já pede

- **Vertical como dado, não como código.** Unidade declara ramo e capabilities (cobrar, agendar,
  mostrar catálogo). Tool, vocabulário de tela e cron leem isso. É o que transforma "fork dos
  hotéis" em produto.
- **Catálogo genérico no lugar de suíte.** Suíte, plano de academia e sala alugada são o mesmo
  objeto: item com preço, foto e disponibilidade.
- **Painel de saúde das conexões como tela.** `Captain::Health::ConexoesService` já existe e é
  exposto por endpoint. Vira tela e para de descobrir agente mudo pelo cliente reclamando.
- **Cron com sinal de vida.** O caso do `NotificationScannerJob` (8.243 jobs mortos sem ninguém
  ver) se repete enquanto cron falhar em silêncio. Heartbeat por job + alerta quando some.
- **Onboarding de cliente como comando.** Já começado em `lib/fazer/onboarding`, hoje parado na
  branch `wip/2026-08-22-snapshot`. Terminar isso faz o próximo cliente custar uma tarde.

## Anexo: organização do repositório (feita nesta sessão)

- Branches locais: 33 → 6 (`main`, `docs/auditoria-fork-2026-08`, `wip/2026-08-22-snapshot`,
  `codex/ia-foto-enviada-label`, `fix/wuzapi-protocol-message`, `archive/rejected-fazer-ai-v4.13.0-64`)
- Branches remotas: 37 → 4 (main + as 2 com PR aberto + a de auditoria quando subir)
- 2 worktrees mortas podadas; a de `codex/gowa-inbox-production` removida após o merge do PR #27
- `main` local atualizada com `origin/main`
- Working tree que estava solto salvo em `wip/2026-08-22-snapshot`
- Tooling local (`.agents/`, `.windsurf/`, `scripts/ralph/`, `skills-lock.json`) movido para
  `.git/info/exclude` — fica no disco, some do `git status`
- `origin` corrigido para `https://github.com/Rodribm10/iachat.git` (casing)
