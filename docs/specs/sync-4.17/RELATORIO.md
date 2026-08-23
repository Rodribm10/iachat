# Sync do fork: 4.11 → 4.17

Branch `sync/4.12`, 6 degraus, 1.109 commits do upstream `fazer-ai/chatwoot`
absorvidos. Este documento registra o que foi **decidido** — o que o git nao
conta sozinho.

## Os degraus

| Degrau | Alvo | Commits | Conflitos |
|---|---|---|---|
| 1 | `v4.12.0-fazer-ai.38` | 152 | 35 |
| 2 | `v4.13.0-fazer-ai.73` | 167 | 22 |
| 3 | `v4.14.2-fazer-ai.84` | 273 | 20 |
| 4 | `v4.15.1-fazer-ai.89` | 83 | 4 |
| 5 | `v4.16.2-fazer-ai.95` | 237 | 42 |
| 6 | `v4.17.0-fazer-ai.96` | 188 | 36 |

## As tres decisoes que se repetiram em todo degrau

### 1. Motor interno do Captain fica desligado

O upstream reintroduz `Agentable`, `AgentRunnerService`,
`ResponseBuilderJob`, os templates `.liquid`, `prompt_context`, `agent_tools` e
`handoff_key` a cada versao. Todos recusados nos 6 degraus. **Hermes e o unico
caminho de resposta.**

Consequencia: as specs do upstream que exercitam esse motor ficam vermelhas
para sempre. Nao sao regressao.

### 2. Ciclo de aprendizado do FAQ e nosso

O 4.16 trouxe o pipeline de `faq_suggestions` deles. Ficou o nosso (dedup +
juiz + quarentena de 30 dias). O job novo deles — que traz mutex por
assistente+idioma — foi mantido e aponta pro nosso servico via
`generate_suggestions` / `language_for`.

### 3. Traducoes migraram para a arquitetura do upstream

O 4.16 criou `app/javascript/dashboard/i18n/fazer-ai/locale/<lang>/`, que faz
deep merge por cima do upstream. Melhor que o que o fork fazia (editar
`locale/<lang>` direto, que conflitava todo sync). Migrado: `captain.json`,
`jasmine.json`, `aggressiveBanner.json`, `groups`, `kanban`, `internalChat` e as
chaves dos provedores wuzapi/gowa/evolution.

**Daqui pra frente:** chave nova do fork vai em `i18n/fazer-ai/locale/<lang>/`,
nunca em `i18n/locale/<lang>/`.

## O que veio do upstream e vale a pena

- **WebhookChannelFinderService** — acha o canal do WhatsApp Cloud tratando
  variacao de numero por pais (Brasil sem o 9, Argentina com digito extra) e
  conferindo o `phone_number_id`. Melhor que a normalizacao que tinhamos.
- **Lock por (inbox, contato) no webhook** — album de fotos chega em webhooks
  concorrentes; sem o lock, cada um criava uma conversa.
- **Modo "converter inbox"** de um provider de WhatsApp para outro.
- **Cap de conversas novas do baileys** exposto na UI.
- **Regra anti-promessa no prompt do assistente**: proibido dizer "vou
  verificar/retornar" sem executar a acao agora.
- **`handoff manda`** no calculo de resolucao do bot.

## Estragos antigos que o sync revelou

Todos vieram do commit `chore(style): fix rubocop offenses and update typing
indicators` (0e7dc282c) ou do degrau 1:

1. `CollaboratorsPage.vue` e `CustomerSatisfactionPage.vue` estavam 1.191 linhas
   atras do upstream.
2. **Webhook nunca era configurado na criacao de inbox de WhatsApp**:
   `after_create_commit` e `after_update_commit` apontavam para o mesmo simbolo
   `:setup_webhooks`, e o Rails deduplica — o de criacao sumia em silencio.
3. `teardown_webhooks` tinha perdido a guarda contra dupla execucao.
4. `channel/whatsapp.rb` com metodos duplicados.
5. `Settings.vue` importava `WuzapiConfiguration`, `GowaConfiguration`,
   `EvolutionGoConfiguration` e `InboxAutoResolve` sem usar nenhum no template —
   quatro telas do fork inacessiveis.
6. `ConfigurationPage.vue` tinha perdido as secoes de baileys e zapi.
7. Playground do Captain chamava `AgentRunnerService`, apagado no dia anterior.
8. `db/schema.rb` tinha indice duplicado — `db:schema:load` quebrava em base nova.
9. **Despacho pro Hermes quebrado no degrau 5** (corrigido no mesmo dia): o
   `trigger_templates` do upstream entrou no lugar do nosso e chamava metodos que
   nao existem deste lado.

## O que continua vermelho (e por que)

Tres familias, nenhuma delas regressao do sync:

1. **Unlock do fork.** `Featurable#feature_enabled?` devolve `true` sempre
   (commit `feat: sync with enterprise unlock recipe`). Toda spec que testa
   comportamento com feature desligada falha. Efeito colateral real: o limite de
   capacidade por agente da inbox nao e respeitado, porque `assignment_v2`
   responde ligada e o caminho V2 so considera agente **online**.
2. **Motor interno removido** (item 1 acima).
3. **Servicos que o fork sobrescreveu de proposito**: hook de templates,
   handoff tool, bulk actions do Captain, metricas do bot.

## Antes de mandar pra producao

O sync toca as 11 inboxes de WhatsApp e telas que a equipe usa todo dia. Em
staging, clicar:

1. Configuracoes de inbox — em uma inbox de cada provider (evolution, wuzapi,
   gowa, baileys, cloud). Foi onde mais se mexeu.
2. Criar uma inbox nova de WhatsApp e conferir que o webhook e configurado.
3. Mandar mensagem de cliente numa inbox com atendente Hermes e ver a resposta
   chegar.
4. Captain → FAQs → Pendentes (quarentena) e a tela de Relatorios IA.
5. Perfil do agente → alerta de conversa parada (o seletor por inbox voltou).
