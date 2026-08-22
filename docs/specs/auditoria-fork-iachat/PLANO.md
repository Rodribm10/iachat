# PLANO — Enxugar o iachat e torná-lo multi-projeto

**Objetivo em uma frase:** deixar o fork com um único motor de atendimento (Hermes), sem código
morto, com cada módulo ligável por projeto no Super Admin, e de volta à linha do upstream.

**Por que merece spec:** toca produção real (atendimento dos hotéis + a conta da academia já
aberta), remove tabela de banco, desliga um caminho de resposta inteiro e termina num merge de
1.102 commits. Errar aqui derruba atendimento de cliente pagante.

**Base:** `docs/auditoria/2026-08-22-auditoria-fork.md` (v2).
**Branch:** `docs/auditoria-fork-iachat` (renomear pra `chore/enxugar-fork` ao começar F1).

> **Regra da planta.** Depois de aprovado, este plano congela. Desvio obrigatório → paro,
> registro o motivo no `RELATORIO.md`, peço re-aprovação. Não altero em silêncio.

---

## Fora de escopo

- Renomear `Captain::Reservation` / `Captain::Unit` para nomes neutros de ramo. O acoplamento é
  de vocabulário, não de arquitetura, e renomear model custa migration + frontend + prompts.
  Fica pra depois do sync, se ainda incomodar.
- Construir o catálogo genérico de produto (substituto de suíte). É feature nova.
- Reconstruir o versionamento de prompt (`captain_prompt_*`). As tabelas saem; a ideia volta
  como feature nova, se você quiser.
- Qualquer mudança nos prompts das atendentes.

---

## F0 — Triagem em produção

**Entrega:** `RELATORIO.md` com cada subsistema classificado em VIVO / MORTO INÚTIL /
PARADO MAS ÚTIL, com o número que sustenta a classificação.

**Precondição — você precisa liberar:** acesso de **leitura** ao Postgres de produção
(stack `iachat` na VPS do Leo). Só `SELECT`. Sem isso F0 não roda e todo o resto vira aposta.

Consultas (uma por linha da tabela da seção 3 da auditoria):

1. `captain_assistants` agrupado por `engine` — quantos ainda em `captain_interno`
2. `captain_units` × `accounts` — quantas contas, quais são hotel e qual é a academia
3. draws de roleta nos últimos 90 dias
4. `captain_lifecycle_deliveries` com `status='sent'` nos últimos 90 dias
5. conversas originadas por `Captain::Retention::ChurnOutreachJob` nos últimos 90 dias
6. `captain_contact_memories` — volume, e se alguma foi injetada em prompt (log/uso)
7. `landing_hosts` ativos e `lead_clicks` recentes
8. `channel_whatsapp` agrupado por `provider` — quais têm inbox viva
9. contagem de linhas nas 16 tabelas órfãs (achar dado que valha exportar antes do drop)
10. `captain_report_snapshots` — confirmar que está vazia/parada

**Saída:** tabela de destino preenchida + lista final do que entra em F1 e do que entra em F4.

---

## F1 — Remover o morto confirmado

**Só entra aqui o que F0 confirmou.** O que já está confirmado por análise estática:

### F1.1 — Jasmine
Apagar `JasmineConfiguration.vue`, `components/JasmineKnowledgeBase.vue`,
`api/inbox/jasmine.js`, `i18n/locale/{en,pt_BR}/jasmine.json` e a chave de registro do i18n.

### F1.2 — Classes órfãs
```
enterprise/app/services/captain/inter/webhook_setup_service.rb
enterprise/app/services/captain/notifications/send_notification_service.rb
enterprise/app/services/captain/tool_registry_service.rb
enterprise/app/services/captain/tools/base_service.rb
app/services/whatsapp/message_dedup_lock.rb
app/services/whatsapp/providers/evolution_api/payload_parser.rb
app/javascript/dashboard/routes/dashboard/settings/captain/units/TestIndex.vue
chatwoot_zero/
```
Mais os specs correspondentes.

### F1.3 — Migration derrubando tabelas órfãs
Uma migration, `drop_table` com bloco `up`/`down` (schema reversível), na ordem das FKs:
`captain_assets` antes de `captain_suites`; `whatsapp_campaign_hits` antes de
`whatsapp_campaigns`; `jasmine_document_chunks` antes de `jasmine_documents`.
Se F0.9 achar linha em tabela que interesse, exportar CSV pra `tmp/` **antes**.

### F1.4 — Limpar `.env.example`
Remover as 11 variáveis de tooling. Se elas forem usadas pelo AIOS, migram pra
`.env.aios.example` fora do caminho do app.

**Fica de fora de F1** (correção da v2): `Reports::ExecutiveController` (está roteado) e a
camada `Captain::Tools::*` (é do motor interno — sai em F3).

---

## F2 — Módulos ligáveis por projeto

**O que você pediu:** tudo que é de um nicho vira campo no admin, ligado/desligado por projeto,
e o que eu criar daqui pra frente já nasce assim.

**Decisão de arquitetura: reusar o mecanismo do Chatwoot, não criar outro.**
`config/features.yml` + `Featurable` + a tela do Super Admin já fazem exatamente isso. O que
falta é espaço: o fork está em **63/63 bits** de `accounts.feature_flags`.

### F2.1 — Backport do `Featurable` multi-coluna
Trazer do upstream (`fazer-ai/main`) o suporte a várias colunas de flags:
- migration adicionando `accounts.feature_flags_ext_1` (bigint, default 0, not null)
- `app/models/concerns/featurable.rb` → `FEATURE_FLAG_COLUMNS`, `MAX_FEATURES_PER_COLUMN = 63`,
  `feature_flag_mappings_for`, `validate_feature_count!`
- suporte à chave `column:` em `config/features.yml`

Feito assim por dois motivos: você ganha a tela de admin de graça, e o fork **converge** com o
upstream em vez de divergir mais — reduz conflito no F5.

### F2.2 — Declarar os módulos do fork
Todos com `column: feature_flags_ext_1`, `enabled: false` (nasce desligado), apendados ao final
do YAML — nunca no meio, o arquivo é posicional.

| Feature | Cobre |
|---|---|
| `captain_units` | multi-unidade, galeria por unidade |
| `captain_reservations` | reservas, marcadores, receita |
| `captain_catalog` | galeria/catálogo de produto (hoje "suítes") |
| `captain_pix_inter` | cobrança PIX via Inter, polling, certificados |
| `captain_pix_manual` | PIX estático + comprovante |
| `captain_roleta` | roleta da sorte |
| `captain_lifecycle` | mensagens programadas com guards |
| `captain_retention` | stats de recorrência + churn outreach |
| `captain_landing_hosts` | landing pages + rastreio de clique |
| `captain_contact_memories` | memórias de contato |
| `captain_executive_reports` | CEO Digest, funil, retenção, insights |
| `captain_construtor` | tools de admin do Construtor |

### F2.3 — Aplicar o gate em quatro camadas

1. **Tools MCP** — `Captain::Mcp::ToolRegistry` passa a filtrar por feature da conta.
   Cada tool declara `self.feature` (`nil` = sempre disponível). O `tools/list` do Hermes da
   academia deixa de enxergar `check_suite_availability`.
   Sempre disponíveis: `add_label`, `faq_lookup`, `update_contact`, `get_contact_history`,
   `react_to_message`, `create_internal_note`.
2. **Crons** — cada job de módulo abre com `next unless account.feature_enabled?('...')` no laço
   de contas. Conta sem o módulo não gera job.
3. **Rotas/controllers** — `before_action` verificando a feature, devolvendo 404.
4. **Dashboard** — item de menu e rota só aparecem com a feature ligada.

### F2.4 — Ligar as features nas contas de hotel
Migration de dados: contas existentes recebem tudo que já usam ligado, pra não haver regressão.
A conta da academia fica só com o núcleo.

**Regra permanente, daqui pra frente:** módulo novo = uma linha em `features.yml` com
`enabled: false` + gate nas quatro camadas. Nada de nicho entra sem interruptor.

---

## F3 — Desligar o Captain interno

**Ordem obrigatória — guardas primeiro.**

### F3.1 — Portar as guardas de vazamento (antes de remover qualquer coisa)
Extrair `SYSTEM_PROMPT_LEAK_PATTERNS` e `THOUGHT_LEAK_PATTERNS` do `ResponseBuilderJob` para um
módulo compartilhado e aplicá-los em `Webhooks::Captain::HermesCallbackController`, com o mesmo
desfecho que o `ERROR_PAYLOAD_PATTERNS` já tem hoje: **não entrega ao cliente, vira nota privada,
marca triagem humana.**
Specs cobrindo cada família de padrão contra o callback do Hermes.

### F3.2 — Remover o motor
```
enterprise/app/jobs/captain/conversation/response_builder_job.rb
enterprise/app/services/captain/assistant/agent_runner_service.rb
enterprise/app/services/captain/llm/assistant_chat_service.rb
enterprise/app/services/captain/codex/{auth_service,client,translator}.rb
enterprise/app/jobs/captain/codex/refresh_tokens_job.rb
enterprise/app/models/captain/codex_credential.rb  + tabela captain_codex_credentials
enterprise/lib/captain/conversation/reaction_policy.rb
enterprise/app/services/captain/tools/*  (menos generate_pix_tool.rb e copilot/*)
config/agents/tools.yml + o loader em captain_tools_helpers.rb
cron captain_codex_refresh_tokens_job
```
`Captain::Tools::GeneratePixTool` fica (usada pelo controller público de reservas).
`captain/tools/copilot/*` fica (é o Copilot do upstream, outro caminho).

### F3.3 — Simplificar o roteador
`Enterprise::MessageTemplates::HookExecutionService#schedule_captain_response` deixa de bifurcar:
sempre Hermes. A coluna `engine` e o fallback por env var (`CAPTAIN_HERMES_INBOX_IDS`) saem.

**Trava de segurança:** F3.2 e F3.3 só rodam se F0.1 devolver zero assistants em
`captain_interno`. Se houver algum, migra primeiro pra Hermes e reconfirma.

---

## F4 — Reativar o "parado mas útil"

O que F0 classificar aqui. Pré-classificado na auditoria, cada um já gated por F2:

- **CEO Digest / relatórios executivos** — o service, o controller e a tela existem. Descobrir
  por que ninguém consome e consertar o elo que falta (provavelmente entrega no Mattermost).
- **Lifecycle** — generalizar o gatilho: hoje só reserva dispara. Passa a aceitar evento genérico,
  pra academia usar (lembrete de aula, renovação de plano).
- **Retenção / churn outreach** — mesmo caso, é o uso mais forte da academia.
- **Saúde das conexões** — `Captain::Health::ConexoesService` vira tela em vez de só endpoint.
- **Cron com sinal de vida** — heartbeat por job agendado + alerta quando um some. É o que teria
  pego o `NotificationScannerJob` (8.243 jobs mortos) e a credencial Codex vencida.
- **Onboarding de cliente** — recuperar de `wip/2026-08-22-snapshot` e terminar.

---

## F5 — Sync com o upstream (4.11.0 → 4.17.0)

1.102 commits. Não é merge de uma sentada.

1. Levantar os conflitos reais: `git merge --no-commit --no-ff fazer-ai/main`, catalogar e abortar.
2. Decidir por subsistema o que abandonar em favor do upstream. Candidato número um: o ciclo de
   aprendizado de FAQ (upstream tem `captain_faq_suggestions` / `captain_faq_observations`).
3. Merge por blocos, com a suíte verde entre eles.
4. Subir em staging (`chatwoot-staging-deploy`) e rodar atendimento real antes de prod.

Ganhos que entram junto: chat interno entre agentes, chamadas de voz, assinatura por inbox, pin
de conversa, desfecho de conversa, mensagens recorrentes, rollup de relatório.

---

## Sequência e portões

```
F0 triagem ──► F1 remoção ──► F2 módulos ──► F3 Captain sai ──► F4 reativações ──► F5 sync
     │              │              │               │
   precisa       precisa        precisa        precisa F3.1
   acesso        de F0          de F0          feito e verde
   ao prod
```

Cada fase fecha com deploy em staging e verificação dos `CRITERIOS.md` daquela fase antes da
próxima começar. F1, F2 e F3 vão pra produção separadamente — não empacotar.

---

## Decisões do Rodrigo — 22/08/2026 (plano CONGELADO a partir daqui)

Tomadas depois do F0, com o dado da triagem na mesa.

| Assunto | Decisão |
|---|---|
| Lifecycle / concierge | **Remover.** Nunca rodou (0 regras, 0 entregas). Se a academia precisar de lembrete, constrói limpo depois do sync. |
| Memórias de contato | **Remover.** 0 registros, 4 crons à toa. |
| Roleta | **Fica.** Está em uso; o estado vive no Supabase, não neste banco. Vira módulo ligável só pras contas de hotel no F6. |
| Providers de WhatsApp | **Não mexer agora.** Revisar depois do sync, com o código do upstream dentro. |
| Autorização em produção | **Aberta.** Deploy e migration liberados, incluindo o `DROP` das tabelas vazias, sem parar pra reconfirmar. Staging antes, sempre. |

### Correção de premissa registrada

O plano original justificava "limpeza antes do sync" com a ideia de chegar leve no merge.
**Medido: falso.** Dos 154 arquivos em colisão fork × upstream, só 8 somem com a limpeza — o
código morto do fork é fork-only e não conflita. A ordem limpeza-antes fica valendo por outro
motivo: é o passo de menor risco e evita resolver conflito em código condenado. A exceção real
é o motor interno do Captain (5 arquivos, ~1.158 linhas, fork +656 / upstream +355−254), esse
sim vale matar antes do merge.

### Ordem de execução final

```
F0  triagem                                    ✅ concluída
F1  remover o morto + lifecycle + memórias     ← executando
F2  portar guardas de vazamento pro Hermes     (antes de F3)
F3  desligar o Captain interno
F4  sync 4.11 → 4.17, em 6 degraus
F5  reativações que a triagem aprovar
F6  módulos no Super Admin (Featurable já vem pronto do sync)
```

Mudança em relação ao plano original: o backport do `Featurable` saiu — o sync entrega ele
pronto. Por isso F6 desceu pra depois de F4.

---

## Regra de deploy — a partir de 22/08/2026

Combinada depois do F1. Vale pra todas as fases seguintes.

```
branch → CI builda imagem → staging (iachat-v2) → Rodrigo testa e APROVA → produção (iachat)
```

- A stack `iachat-v2` fica **em repouso** (app/sidekiq/redis em 0, postgres em 1). Subir é
  `docker service scale` + `--image` na tag nova.
- **Mudança de schema:** restaurar dump de produção no `iachat_staging` **antes** de migrar.
  Testar migration contra banco limpo não prova nada.
- Esse dump deixa dado real de cliente no staging: **apagar banco e dump** assim que a validação
  terminar, e devolver a stack ao repouso.
- **Em produção:** código primeiro, migration depois. No intervalo, rollback de imagem funciona.
- Tag da imagem = `github.run_number` do CI, nunca `:latest`.

No F1 esse fluxo foi cumprido pela metade: a validação técnica em staging foi feita (migration
contra dump real), mas o Rodrigo não chegou a testar antes de eu subir — ele mandou seguir direto.
Deu certo, mas não vira precedente.
