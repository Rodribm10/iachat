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

**Decidido:** o motor interno sai. O Hermes fica como único caminho de resposta.

### Antes de desligar: as guardas de vazamento só existem no caminho interno

`Captain::Conversation::ResponseBuilderJob` carrega ~30 regexes endurecidas ao longo do tempo
(`SYSTEM_PROMPT_LEAK_PATTERNS` + `THOUGHT_LEAK_PATTERNS`) que bloqueiam o LLM devolver o system
prompt, narrar instrução interna, vazar nome de tool (`handoff_to_`, `daniela_reservas`), JSON
cru ou Liquid não renderizado — e forçam handoff humano quando detectam.

O caminho do Hermes tem outras guardas: `ERROR_PAYLOAD_PATTERNS` (nasceu do incidente de
25/07/2026, quando cliente do Instagram leu "HTTP 401"), detecção de loop por Jaccard e
`HANDOFF_PATTERNS`. **Mas não tem as de vazamento de prompt/pensamento.**

Isso é o exemplo mais claro de "morto mas útil": desligar o motor sem portar essas regexes
para `Webhooks::Captain::HermesCallbackController` é abrir mão de proteção que já custou
incidente. Portar é pré-requisito, não melhoria.

`Captain::Conversation::ReactionPolicy` **não** precisa ser portada — o caminho do Hermes já
tem `Captain::Hermes::AutoReactService`, que faz o mesmo de forma determinística e mais rápida.

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

> **Correção (v2).** Na primeira versão eu disse "zero referências". Está errado.
> Essas classes são resolvidas **dinamicamente** por
> `enterprise/app/models/concerns/captain_tools_helpers.rb:47`, que lê
> `config/agents/tools.yml` e faz `Captain::Tools::{PascalCase(id)}Tool`.
> Todas as seis estão listadas no YAML. Ou seja: **não são código órfão — são a
> camada de tools do motor interno.** Saem junto com o motor (passo 5), não antes.

Duplicadas pelas equivalentes em `captain/mcp/tools/`, que é o que o Hermes usa:

```
Captain::ToolRegistryService              (esse sim: zero referências)
Captain::Tools::BaseService               (esse sim: zero referências)
Captain::Tools::CheckPixPaymentTool       ┐
Captain::Tools::CreateReservationIntentTool │ alcançáveis via tools.yml
Captain::Tools::GenerateReservationLinkTool │ morrem com o motor interno
Captain::Tools::GenerateRoletaLinkTool     │
Captain::Tools::GetReservaPrecoTool        │
Captain::Tools::SendSuiteImagesTool       ┘
```

Exceção: `Captain::Tools::GeneratePixTool` também é usada por
`Public::Api::V1::Captain::PublicReservationsController` (fluxo da landing page) —
essa sobrevive ao desligamento do motor.

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

Cada uma re-verificada: aparece só no próprio arquivo, em `app/`, `enterprise/`,
`lib/`, `config/` e `db/`.

```
Captain::Inter::WebhookSetupService               sem chamador
Captain::Notifications::SendNotificationService   sem chamador
Whatsapp::MessageDedupLock                        sem chamador
Whatsapp::Providers::EvolutionApi::PayloadParser  sem chamador
settings/captain/units/TestIndex.vue              órfão (29 linhas)
chatwoot_zero/                                    2 PNGs de uma cópia velha
```

> **Correção (v2).** `Api::V1::…::Reports::ExecutiveController` **não** está morto —
> está roteado em `config/routes.rb:120` (`resource :executive` com `drilldown` e
> `deliver`) e é o que alimenta a tela `settings/captain/reports`. A primeira versão
> disse "sem rota" por causa de um erro no meu próprio grep. **Fica.**

`Captain::Reports::DailySnapshotJob` saiu desta lista por outro motivo: ele não tem
entrada no `schedule.yml` (embora o comentário dele diga que roda à meia-noite) **e**
ninguém lê `Captain::ReportSnapshot`. Hoje é um gravador sem leitor e sem gatilho —
decisão sobre ele na triagem (seção 3), não na remoção cega.

### Higiene: `.env.example`

Credenciais de ferramenta de desenvolvimento documentadas como se fossem config do app:
`CLICKUP_API_KEY`, `RAILWAY_TOKEN`, `VERCEL_TOKEN`, `GITHUB_TOKEN`, `N8N_API_KEY`,
`N8N_WEBHOOK_URL`, `AIOS_VERSION`, `CONTEXT7_API_KEY`, `EXA_API_KEY`, `DEEPSEEK_API_KEY`,
`OPENROUTER_API_KEY`.

## 3. Triagem — três destinos, não dois

A pergunta não é "está vivo?". É **"vale a pena?"**. Cada subsistema cai em um de três destinos:

- **VIVO** — está em uso, fica como está
- **MORTO INÚTIL** — específico demais ou superado, sai
- **PARADO MAS ÚTIL** — não roda (ou roda e ninguém olha), mas o conceito serve o negócio,
  inclusive fora de hotelaria. **Conserta e liga**, não apaga.

O terceiro destino é o que a primeira versão desta auditoria não tinha, e é onde está o
dinheiro: código já escrito, já testado, parado por falta de um cron, de uma rota ou de uma tela.

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

### Palpite prévio de destino (a confirmar com o banco)

Escrito antes das consultas, de propósito — pra ficar registrado onde eu errei quando o dado chegar.

| Subsistema | Palpite | Por quê |
|---|---|---|
| Lifecycle / concierge | **parado mas útil** | mensagem programada com guards de quiet hours, opt-out e teto por reserva é infra genérica. Numa academia vira lembrete de aula e aviso de renovação. Trocar "reserva" pelo evento certo e liga. |
| Retenção / churn outreach | **parado mas útil** | "cliente recorrente sumiu há 60 dias" é o caso de uso mais forte de academia que existe. Já calcula stats, já tem janela comercial e dia útil. |
| CEO Digest + insights | **parado mas útil** | o service roda, o controller existe e está roteado, a tela existe. Se ninguém lê o Mattermost, o problema é canal de entrega, não o relatório. |
| Memórias de contato | **confirmar primeiro** | 4 crons + embeddings custam caro. Se não entra no prompt do Hermes hoje, ou liga direito ou desliga inteiro — meio-termo é só custo. |
| `Captain::Health::ConexoesService` | **parado mas útil** | já existe e é exposto por endpoint. Falta tela. É o que evita descobrir agente mudo pelo cliente reclamando. |
| Roleta | **morto inútil** (provável) | promoção de motel, sem leitura em outro ramo. Se o draw parou, sai. |
| `DailySnapshotJob` + `captain_report_snapshots` | **morto inútil** | grava e ninguém lê, e nem cron tem. Só vira útil se houver tela de série histórica — que não existe. |
| Landing hosts + lead clicks | **confirmar primeiro** | cron de hora em hora. Se tem host ativo é vivo; se não, sai junto com `LeadClick` e `TrackingController`. |
| `captain_prompt_*` (6 tabelas) | **ideia boa, código não existe** | versionar e auditar prompt é útil de verdade, mas não sobrou Ruby nenhum. Isso é feature nova, não reativação: as tabelas saem agora. |
| Onboarding (`lib/fazer`) | **parado mas útil** | tem spec escrito, está na branch `wip/2026-08-22-snapshot`. É o que faz o próximo cliente custar uma tarde. |

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
no `tools/list` dela.

### O interruptor por projeto já existe no Chatwoot — e o fork nunca usou

O Chatwoot tem exatamente o mecanismo que você quer: `config/features.yml` declara cada módulo,
o concern `Featurable` guarda os bits em `accounts.feature_flags`, `account.feature_enabled?('x')`
consulta, e o **Super Admin já renderiza as caixinhas de liga/desliga por conta** em
`app/views/super_admin/accounts/show.html.erb`.

O fork adicionou **zero** feature flags. Roleta, lifecycle, units, gallery, reservas, PIX Inter,
landing hosts, retenção — tudo entrou sem interruptor. É por isso que hoje não dá pra abrir uma
conta de outro ramo sem levar o hotel junto.

**Só que tem um bloqueio concreto:** o mecanismo está **lotado**.

```
accounts.feature_flags       → bigint = 63 bits utilizáveis
config/features.yml (fork)   → 63 features
```

Não cabe nem mais uma. E o arquivo é posicional ("DO NOT change the order of features EVER").

O upstream já resolveu isso — na versão 4.17.0 o `Featurable` suporta várias colunas
(`feature_flags_ext_1`, `MAX_FEATURES_PER_COLUMN = 63`, com a chave `column:` por feature).
Então o caminho é **backport dessa mudança do upstream** (1 migration + o concern), e aí cada
módulo do fork vira uma feature normal na coluna de extensão, com a tela de admin de graça e
sem brigar com a ordenação do upstream no próximo sync.

Com isso no lugar, o resto encaixa: `ToolRegistry` filtra tool por feature da conta, os crons
pulam conta sem a feature, e o menu do dashboard esconde o que não se aplica. Módulo novo que
você criar entra desligado por padrão e não vaza pra empresa nenhuma.

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

Detalhada, com critérios de aceitação, em **`docs/specs/auditoria-fork-iachat/`**
(`PLANO.md`, `CRITERIOS.md`, `RELATORIO.md`).

Resumo das cinco frentes, nesta ordem:

1. **Triagem** — consultas de leitura em produção classificando cada subsistema em
   VIVO / MORTO INÚTIL / PARADO MAS ÚTIL.
2. **Remoção do morto confirmado** — Jasmine, classes órfãs, 16 tabelas, `chatwoot_zero/`,
   limpeza do `.env.example`.
3. **Módulos por projeto** — backport do `Featurable` multi-coluna do upstream e transformação
   de cada módulo do fork em feature ligável no Super Admin, desligada por padrão.
4. **Desligamento do Captain interno** — portar as guardas de vazamento primeiro; depois sai o
   agent runner, o chat LLM, o cliente Codex, o cron de 30 min, o `tools.yml` e a camada
   `Captain::Tools::*` (menos `GeneratePixTool`).
5. **Sync com o upstream** — 4.11.0 → 4.17.0.

A conta da academia **já está aberta** — o que falta pra ela é o passo 3.

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

## Histórico de revisões

**v2 — 22/08/2026.** Revisão após leitura mais funda do código e direção nova do Rodrigo.

Corrigido:

- `Reports::ExecutiveController` estava marcado como "sem rota". **Errado** — está em
  `config/routes.rb:120`. O erro foi meu, num grep com escape quebrado.
- A camada `Captain::Tools::*` estava marcada como "zero referências". **Errado** — é resolvida
  dinamicamente por `config/agents/tools.yml`. Morre com o motor interno, não antes.

Acrescentado:

- Guardas de vazamento de prompt existem só no caminho interno; portar é pré-requisito do
  desligamento do Captain.
- `config/features.yml` está em 63/63 bits — o mecanismo de liga/desliga por conta existe, mas
  está lotado; o upstream já tem a solução multi-coluna.
- Triagem passou a ter três destinos (VIVO / MORTO INÚTIL / PARADO MAS ÚTIL) em vez de dois.
- A conta da academia já foi aberta; deixou de ser passo do plano.
