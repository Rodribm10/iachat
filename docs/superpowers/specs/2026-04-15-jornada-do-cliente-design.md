# Jornada do Cliente — Lifecycle Automation

**Data:** 2026-04-15
**Status:** Design aprovado, pronto pra plano de implementação
**Sub-skill de implementação recomendada:** superpowers:writing-plans

## 1. Visão geral

Sistema de automação de mensagens WhatsApp acionadas por eventos do ciclo de vida de uma reserva. O operador do hotel (via Chatwoot fazer.ai) cria regras pela UI — cada regra define "quando" (evento + offset), "pra quem" (filtros de unidade/categoria/permanência) e "o que" (mensagem com variáveis e botões interativos). O sistema dispara as mensagens via WuzAPI na inbox da concierge da unidade. Se o cliente responder, uma AI concierge ("Sofia") assume a conversa com base de conhecimento específica daquela unidade.

**Arquitetura multi-tenant:** hybrid (C) — já nasce com banco/código preparados pra qualquer conta do fazer.ai configurar suas próprias jornadas, mas o MVP é validado com as 4 unidades do Grupo 1001.

## 2. Contexto e motivação

Hoje, depois que o cliente paga o Pix da reserva, ele só ouve do hotel no check-in ou no check-out (se ouvir). Isso é oportunidade perdida de 3 formas:

1. **Pré-estadia**: cliente chega inseguro (não sabe onde estacionar, wi-fi, regras). Pequena fricção que reduz NPS.
2. **In-stay**: cliente não sabe que existe cardápio, upgrades, extras. Receita adicional perdida.
3. **Pós-estadia**: cliente sai sem oportunidade fácil de avaliar no Google ou responder NPS. Taxa de review orgânico cai.

Lifecycle marketing resolve os três. Hotéis grandes lá fora já fazem isso há anos. A maioria dos concorrentes brasileiros não faz, então entrega vantagem competitiva real.

Como a Chatwoot fazer.ai é a plataforma que o Grupo 1001 usa (e que é vendida pra outros hotéis), a feature tem que nascer como produto reutilizável, não hack interno.

## 3. Arquitetura

Quatro componentes isolados. Cada um tem uma responsabilidade:

```
┌─────────────────────────────────────────────────────────────┐
│  1. Rules Engine (config)                                   │
│  O usuário cria/edita regras pela UI: evento + offset +     │
│  filtro + mensagem + guards. Vive em banco (jsonb).         │
└─────────────────────────────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────┐
│  2. Scheduler (event-driven, NÃO cron)                      │
│  Escuta eventos do domínio (reservation.confirmed etc).     │
│  Pra cada reserva que bate no filtro de alguma regra,       │
│  calcula fire_at e enfileira Sidekiq job agendado.          │
│  Ajusta se a reserva mudar (cancelou → cancela jobs).       │
└─────────────────────────────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────┐
│  3. Dispatcher (runtime)                                    │
│  Quando o job dispara: checa guards (quiet hours, max-5,    │
│  label opt-out, etc), renderiza template Liquid com as      │
│  variáveis, chama Wuzapi::Client pela inbox concierge,      │
│  grava resultado na tabela de delivery (auditoria).         │
└─────────────────────────────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────┐
│  4. Concierge AI (Sofia, reativa)                           │
│  Separada. Captain::Assistant compartilhado entre unidades, │
│  ligado à inbox concierge. Quando o cliente responde, a     │
│  Sofia assume a conversa e responde com base no knowledge   │
│  da unidade da reserva ativa (injetado dinamicamente via    │
│  Liquid no system prompt).                                  │
└─────────────────────────────────────────────────────────────┘
```

**Por que event-driven e não cron de 1-em-1 minuto:** a gente sabe exatamente quando cada mensagem precisa sair no momento em que a reserva é criada (`check_in_at` + regras + offsets → `fire_at` determinístico). Calcula uma vez, enfileira `Sidekiq.perform_at(fire_at)` e deixa o Sidekiq acordar no horário. Barato, preciso, sem risco de "e se o cron atrasar". Um cron mínimo de 1-em-1-min existe apenas pra liberar mensagens que estavam paradas por quiet hours ou retry de erro.

**Regra de privacidade dura:** uma reserva feita em Águas Lindas só pode gerar mensagem saindo da inbox concierge de Águas Lindas. Não existe opção de "mandar a partir de outra unidade". Isso não é configuração, é invariante do sistema.

**Single number, many units (cérebro dinâmico):** a ideia é que um único número WhatsApp possa servir de concierge pra várias unidades de uma conta, mas cada unidade tem sua própria base de conhecimento. Quando um cliente responde, o sistema identifica qual unidade ele reservou (via `conversation.custom_attributes['current_unit_id']` setado pelo lifecycle dispatcher) e injeta **só o knowledge daquela unidade** no system prompt da Sofia via Liquid render. Zero vazamento cruzado.

## 4. Eventos disponíveis

Lista hardcoded (usuário não cria eventos novos, escolhe da lista). Adicionar evento novo é mudança de schema + scheduler.

| Evento | O que dispara |
|---|---|
| `reservation.confirmed` | Pix pago (ou marcado como pago manualmente) |
| `checkin.scheduled_at` | Horário agendado de check-in (base pra offsets negativos tipo -10min, -1h, -1dia) |
| `checkin.detected` | Sistema detectou entrada real (fora de escopo no MVP — deferido, ver backlog) |
| `checkout.scheduled_at` | Horário agendado de checkout |
| `checkout.detected` | Saída real detectada (fora de escopo no MVP) |
| `reservation.cancelled` | Cliente ou operador cancelou |
| `reservation.no_show` | Passou do horário + tolerância e não entrou |

**Offset suportado por regra:** `N minutos/horas/dias antes` ou `depois` do evento. Armazenado como `integer signed` em minutos. Exemplo: `-10` = 10min antes, `+600` = 10h depois.

**Caso especial suportado:** `"às HH:MM do dia anterior ao evento"` (ex: enviar lembrete sempre às 18h do dia antes do check-in). Implementado como offset relativo à meia-noite do dia anterior.

**`checkin.detected` e `checkout.detected`** aparecem na lista mas geram erro "evento ainda não disponível" no MVP. A infra do scheduler já reserva os slots; a detecção real entra em fase 2.

## 5. Modelo de dados

Três tabelas novas + duas colunas em `captain_units`.

### 5.1. `captain_lifecycle_rules`

| Coluna | Tipo | Descrição |
|---|---|---|
| `id` | bigint | PK |
| `account_id` | bigint | FK, scope por conta |
| `name` | string | "Lembrete 10min antes check-in" |
| `description` | text | opcional, ajuda o usuário |
| `enabled` | boolean | liga/desliga sem deletar |
| `event` | string | um dos 7 eventos da seção 4 |
| `offset_minutes` | integer | signed |
| `filters` | jsonb | `{ unit_ids: [1,2], categorias: ["Alexa"], permanencias: ["Pernoite"] }` |
| `message_type` | string | `text`, `buttons`, `list`, `url_button` |
| `message_body` | text | template Liquid |
| `message_payload` | jsonb | botões/lista estruturados (null se `text`) |
| `priority` | integer | 0-100. Quando 2 regras disparam juntas, menor prioridade vai primeiro |
| `created_by_user_id` | bigint | auditoria |
| `created_at/updated_at` | datetime | |

**Nota:** não existe campo `send_via_inbox_id`. A inbox é sempre derivada de `reservation.unit.concierge_inbox`, inviolável.

**Formato do `message_payload` pra botões interativos (estruturado):**

```json
// Quick reply
{ "type": "quick_reply", "body": "Curtiu sua estadia?", "buttons": [
  { "id": "rate_now", "text": "Avaliar agora" },
  { "id": "rate_later", "text": "Mais tarde" }
]}

// URL button
{ "type": "url_button", "body": "Avalie no Google e ganhe um brinde",
  "button": { "url": "{{ hotel.google_review_link }}", "text": "Avaliar" }}

// List menu (até 10 opções)
{ "type": "list", "body": "Nosso cardápio:", "button_text": "Ver opções",
  "sections": [{ "title": "Bebidas", "rows": [...] }]}
```

Strings dentro do payload também passam pelo Liquid render.

### 5.2. `captain_lifecycle_deliveries` (audit log)

Toda tentativa de envio vira 1 linha aqui, não importa se saiu, foi pulada ou falhou. Fonte da verdade pro guard max-5, histórico por reserva e dashboard.

| Coluna | Tipo | Descrição |
|---|---|---|
| `id` | bigint | PK |
| `account_id` | bigint | FK |
| `lifecycle_rule_id` | bigint | FK (nullable — se regra foi deletada depois) |
| `captain_reservation_id` | bigint | FK — a reserva alvo |
| `conversation_id` | bigint | FK (null até mensagem ser enviada) |
| `message_id` | bigint | FK (null até mensagem ser enviada) |
| `inbox_id` | bigint | FK |
| `fire_at` | datetime | quando estava agendado pra sair |
| `sent_at` | datetime | quando saiu de fato (null se skipped/failed) |
| `status` | string | `scheduled`, `sent`, `skipped`, `failed`, `cancelled` |
| `skip_reason` | string | `quiet_hours`, `too_stale`, `max_reached`, `opt_out_label`, `customer_replied`, `min_interval`, `reservation_cancelled` |
| `failure_reason` | text | erro da API se `failed` |
| `rendered_body` | text | o texto final enviado (variáveis já substituídas) — auditoria forense |
| `origin` | string | `scheduled_lifecycle` — marca as que contam no cap de 5 |

**Índices críticos:**
- `(captain_reservation_id, origin, status)` — pro cap de 5
- `(account_id, status, fire_at)` — pro dashboard
- `(lifecycle_rule_id)` — pro histórico da regra
- `(fire_at)` parcial WHERE status='scheduled' — pra retries e re-enfileiramento

**Política de retenção:** job noturno apaga linhas `sent/skipped/cancelled` com mais de 180 dias. Linhas `failed` e `scheduled` nunca expiram automaticamente.

### 5.3. `captain_lifecycle_configs` (guards globais por conta)

Uma linha por `account_id`. Guards configuráveis via UI.

| Coluna | Tipo | Default | Descrição |
|---|---|---|---|
| `account_id` | bigint | — | PK + FK |
| `quiet_hours_enabled` | boolean | `false` | desligado por default |
| `quiet_hours_from` | time | `"23:00"` | |
| `quiet_hours_to` | time | `"08:00"` | |
| `min_interval_minutes` | integer | `30` | `0` desativa |
| `pause_on_customer_reply` | boolean | `false` | desligado por default |
| `pause_on_customer_reply_within_minutes` | integer | `60` | |
| `opt_out_label_id` | bigint | null | FK → `labels` |

**Factory default forçado (não fica na tabela, é constante no código):** max 5 mensagens `origin=scheduled_lifecycle` por reserva. Não dá pra desligar nem aumentar.

### 5.4. Novas colunas em `captain_units`

| Coluna | Tipo | Descrição |
|---|---|---|
| `concierge_inbox_id` | bigint | FK → inboxes. Qual inbox WhatsApp é a concierge dessa unidade. Pode ser a mesma pra várias unidades. |
| `concierge_config` | jsonb | `{ persona_name, knowledge, variables }` |

**Schema do `concierge_config`:**

```json
{
  "persona_name": "Sofia",
  "knowledge": "## Sobre o hotel\n...\n## Regras\n...\n## Café da manhã\n...",
  "variables": {
    "wifi_password": "hotel1001",
    "menu_link": "https://menu.hotel.com",
    "google_review_link": "https://g.page/r/...",
    "address": "Rua X, 123 - Águas Lindas"
  }
}
```

`knowledge` é markdown longo que vai pro system prompt da Sofia. `variables` é key/value curto pra substituição em templates (`{{ hotel.wifi_password }}`).

## 6. Fluxo de execução

### 6.1. Criação de reserva

```
Captain::Reservation after_commit(:create)
    │
    ▼
LifecycleRuleScheduler.schedule_for(reservation)
    │
    ├─ Query: lifecycle_rules WHERE enabled AND event matches
    │        AND filters match (unit, categoria, permanencia, brand)
    │
    └─ Pra cada regra que bateu:
         ├─ fire_at = resolve_event_timestamp(reservation, rule.event) + rule.offset_minutes
         ├─ Se fire_at < Time.current → skip (já passou)
         ├─ Cria captain_lifecycle_deliveries com status='scheduled'
         └─ Sidekiq: LifecycleDispatcherJob.perform_at(fire_at, delivery.id)
```

### 6.2. Mudanças na reserva

```
Captain::Reservation after_update
    │
    ▼
Se status mudou pra cancelled/no_show:
    └─ Marca todas as deliveries ainda scheduled dessa reserva como cancelled
       (jobs Sidekiq acordam mas veem status != scheduled e abortam)

Se check_in_at mudou:
    ├─ Marca deliveries scheduled baseadas em checkin.* como cancelled
    └─ Reagenda com novo fire_at chamando LifecycleRuleScheduler de novo
```

**Por que marca como cancelled em vez de apagar da fila do Sidekiq:** mexer na fila é caro e flaky. Mais confiável o job acordar e conferir o status da delivery.

### 6.3. Mudanças na regra (editada pela UI)

```
LifecycleRule after_save
    │
    ▼
Se enabled virou false OU evento/offset/filtros mudaram:
    ├─ Cancela deliveries scheduled dessa regra
    └─ Se enabled=true, recompila pra reservas futuras cujo evento ainda não passou
```

Política: **edição só afeta pra frente**. Reservas cujo evento já aconteceu não recebem reenvio retroativo.

### 6.4. Dispatcher pipeline (job disparou)

```
LifecycleDispatcherJob.perform(delivery_id)
    │
 1. Carrega delivery. Se status != scheduled → abort
    │
 2. Guards (ordem importa, mais barato primeiro):
    ├─ Reserva ainda existe e não está cancelled? Se não → skip(reservation_cancelled)
    ├─ Label opt-out está no contato? → skip(opt_out_label)
    ├─ Max-5 atingido pra essa reserva (count deliveries status=sent, origin=scheduled_lifecycle)? → skip(max_reached)
    ├─ Está dentro do quiet hours (se habilitado)? → reagenda OU skip(too_stale) conforme regra Opção C
    ├─ Intervalo mínimo violado? → reagenda +N min
    └─ Cliente respondeu nos últimos N min (se guard habilitado)? → reagenda +N min
    │
 3. Renderiza o template (Liquid strict mode):
    ├─ Context: customer.*, reservation.*, hotel.* (do concierge_config.variables da unit)
    ├─ Liquid.render(message_body)
    ├─ Se message_type != text: renderiza message_payload (botões/lista) recursivamente
    └─ Salva em delivery.rendered_body
    │
 4. Resolve a inbox:
    └─ inbox = reservation.unit.concierge_inbox  (FAIL se null)
    │
 5. Envia:
    ├─ Resolve/cria Conversation (contact + inbox)
    ├─ Seta conversation.custom_attributes['current_unit_id'] = reservation.captain_unit_id
    ├─ Messages::MessageBuilder(concierge_assistant, conversation, {content, message_type: outgoing}).perform
    ├─ Se tiver botões/lista: WuzapiService.send_buttons/list(...) (método novo)
    └─ Atualiza delivery: status='sent', sent_at, message_id, conversation_id
    │
 6. Erro HTTP/exceção não capturada:
    └─ status='failed', failure_reason=erro, Sidekiq retry policy (3 tentativas com backoff)
```

### 6.5. Quiet hours — Opção C (limite de 2h de atraso)

Se `fire_at` cai dentro da janela `quiet_hours_from..quiet_hours_to`:

- Calcula `delayed_fire_at` = próximo horário válido após a janela
- Se `delayed_fire_at - fire_at > 2h` → **skip com `skip_reason=too_stale`** (mensagem perdeu relevância)
- Senão → reagenda delivery pra `delayed_fire_at`, enfileira novo job

Limite de 2h é constante global no código, não configurável no MVP.

### 6.6. Cliente responde → Sofia assume

Nenhum código adicional além de garantir que `conversation.custom_attributes['current_unit_id']` foi setado no passo 5.5. O Chatwoot já roteia mensagens entrantes pro `Captain::Assistant` da inbox. A Sofia processa normalmente — o orchestrator prompt dela já está configurado com Liquid pra ler `current_unit_id` e injetar o knowledge correto.

## 7. Concierge AI (Sofia)

### 7.1. Modelo

Um `Captain::Assistant` novo (tipo concierge, ou flag) por conta. Ligado a 1+ inboxes via `captain_inboxes`. Normalmente 1 Sofia por conta compartilhada entre todas as unidades, mas o usuário pode criar múltiplas se quiser personas diferentes.

### 7.2. Injeção dinâmica de contexto (core)

O `orchestrator_prompt` da Sofia é um template Liquid. O framework disponibiliza as seguintes variáveis no render context, resolvidas a partir de `conversation.custom_attributes['current_unit_id']` → `captain_units.find(id)`:

- `{{ concierge.persona_name }}` — `concierge_config.persona_name` (default "Sofia")
- `{{ concierge.unit_name }}` — `captain_units.name`
- `{{ concierge.knowledge }}` — `concierge_config.knowledge` (markdown)
- `{{ concierge.variables.X }}` — qualquer chave de `concierge_config.variables`
- `{{ reservation.suite }}`, `{{ reservation.check_in_at }}`, `{{ reservation.check_out_at }}`, `{{ reservation.amount }}`, `{{ reservation.permanencia }}`
- `{{ customer.name }}`, `{{ customer.first_name }}`, `{{ customer.phone }}`

A implementação usa o mecanismo Liquid que o Captain já tem (`{% render 'conversation' %}`, `{% render 'contact' %}`) — adiciona um novo `{% render 'concierge' %}` que resolve via `current_unit_id`.

### 7.3. O que é hardcoded pelo framework

- Tipo/flag do assistente + mecanismo de roteamento
- Variáveis Liquid disponíveis no contexto
- Tools disponíveis no catálogo: `handoff`, `add_label_to_conversation`
- Dispatcher setando `current_unit_id` antes de enviar

### 7.4. O que é configurável pelo dono do hotel

- `orchestrator_prompt` inteiro — ele escreve tom, persona, regras de handoff, transparência de IA, tudo
- `concierge_config.persona_name` por unidade
- `concierge_config.knowledge` por unidade
- `concierge_config.variables` por unidade
- Quais tools a Sofia usa

### 7.5. Template inicial sugerido

O framework entrega um template de `orchestrator_prompt` pronto pra usuário partir dele. Estrutura proposta:

```liquid
Você é {{ concierge.persona_name }}, assistente virtual do {{ concierge.unit_name }}.

## Base de Conhecimento
{{ concierge.knowledge }}

## Dados da Estadia
- Suíte: {{ reservation.suite }}
- Check-in: {{ reservation.check_in_at }}
- Check-out: {{ reservation.check_out_at }}

## Como se comportar
[Escreva aqui o tom, transparência de IA, regras de handoff, etc]
```

Template é só sugestão. Usuário apaga e reescreve se quiser.

### 7.6. Modelo LLM

Mesmo da Jasmine: `gpt-4o` via provider `openai` já configurado.

### 7.7. Sem cenários

Sofia não usa `Captain::Scenario`. Knowledge é monolítico no orchestrator, persona única, fluxo único (pós-venda de uma estadia).

## 8. Variáveis disponíveis

### 8.1. Variáveis do cliente

- `{{ customer.name }}` — Nome completo
- `{{ customer.first_name }}` — Só o primeiro nome
- `{{ customer.phone }}` — Telefone
- `{{ customer.cpf }}` — CPF (se disponível)

### 8.2. Variáveis da reserva

- `{{ reservation.suite }}` — "Alexa", "Stilo", etc
- `{{ reservation.unit_name }}` — "Prime Águas Lindas"
- `{{ reservation.check_in_at }}` — Formatado amigável (ex: "hoje às 22h", "amanhã às 14h")
- `{{ reservation.check_out_at }}` — Idem
- `{{ reservation.amount }}` — "R$ 160,00"
- `{{ reservation.permanencia }}` — "Pernoite", "2hrs", etc

### 8.3. Variáveis da unidade (hotel)

Qualquer chave definida em `captain_units.concierge_config.variables`. Exemplos:

- `{{ hotel.wifi_password }}`
- `{{ hotel.menu_link }}`
- `{{ hotel.google_review_link }}`
- `{{ hotel.address }}`

O usuário cadastra quais chaves existem na config da unidade. O editor de mensagens mostra autocomplete com as chaves disponíveis na unidade selecionada.

## 9. UI — Jornada do Cliente

Nova aba dentro do menu Captain, chamada **"Jornada do Cliente"**, com 3 tabs.

### 9.1. Tab Regras

**Lista principal** em tabela:

| Nome | Evento | Offset | Filtro | Último envio | Taxa sucesso | Status | Ações |
|---|---|---|---|---|---|---|---|
| Lembrete pré check-in | `checkin.scheduled_at` | -10min | Todas unidades · Pernoite | há 2h | 98% | ✅ ativo | Editar / Duplicar / Desativar |

**Templates prontos** (cards no topo da tab): 5-8 templates populares que o usuário pode clonar com 1 clique — lembrete pré check-in, welcome in-stay, pedido de review, etc. Ao clicar, abre o wizard com campos já preenchidos.

**Wizard de 4 passos** pra criar/editar regra:

1. **Quando?** — dropdown de evento + offset (número + unidade minutos/horas/dias + direção antes/depois)
2. **Pra quem?** — multi-select de unidades (obrigatório) + filtros opcionais (categorias, permanências)
3. **O quê?** — editor de mensagem com autocomplete de variáveis + toggle "Incluir botões interativos"
4. **Revisão** — resumo + estimativa "quantas reservas dos últimos 30 dias teriam recebido essa msg" (sanity check)

**Editor de mensagem** tem:
- Textarea com autocomplete quando digita `{{`, listando variáveis disponíveis
- Tooltip em cada variável explicando o que ela vira no render
- Botão "Ver preview" com reserva exemplo
- Seção de botões interativos (se toggle ligado): escolhe tipo (quick_reply / url_button / list), adiciona opções

### 9.2. Tab Configurações

Formulário simples:

- **Quiet hours** (toggle + 2 time pickers, default desligado)
- **Intervalo mínimo entre mensagens** (default 30min, 0 desliga)
- **Pausar se cliente respondeu** (toggle + input "nos últimos X min", default desligado)
- **Label de opt-out** (dropdown de labels da conta)
- **Max mensagens por estadia: 5** (info, não editável)

**Seção "Concierge (Sofia) por Unidade":** lista as `captain_units` com expand por unidade:

- `concierge_inbox_id` (dropdown das inboxes WhatsApp)
- `concierge_config.persona_name` (input text, default "Sofia")
- `concierge_config.knowledge` (textarea markdown grande)
- `concierge_config.variables` (tabela editável de key/value)

### 9.3. Tab Histórico

Lista paginada da `captain_lifecycle_deliveries` dos últimos 30 dias. Filtros: regra, reserva, status, data. Colunas:

| Regra | Cliente | Reserva (link) | Status | Disparado em | Motivo (se skip) | Ações |

Coluna "Ações" tem um botão **Preview** que abre modal com `rendered_body` daquela entrega específica — serve pra debug ("por que a mensagem saiu estranha?") e auditoria.

## 10. Guards anti-spam

### 10.1. Factory default forçado (hardcoded)

**Max 5 mensagens `origin=scheduled_lifecycle` por reserva.** Não é configurável, não pode ser desligado. Se a 6ª regra tentar disparar pra mesma reserva, é descartada silenciosamente com `skip_reason=max_reached`. Cinto de segurança anti-ban crítico pra evitar que uma configuração errada do usuário derrube o número.

### 10.2. Configuráveis (Tab Configurações)

- **Quiet hours** — janela de silêncio. Se habilitado, mensagem dentro da janela usa regra Opção C (reagenda ou skip by too_stale conforme limite de 2h)
- **Intervalo mínimo** — tempo mínimo entre 2 mensagens proativas pro mesmo contato
- **Pausar se cliente respondeu** — se o contato enviou qualquer mensagem nos últimos N min
- **Label de opt-out** — se o contato tem a label escolhida, pula todas as mensagens silenciosamente

### 10.3. Origin distinction

Só mensagens com `origin=scheduled_lifecycle` contam no cap de 5 e no intervalo mínimo. Mensagens geradas pela Sofia respondendo cliente em tempo real (`origin=concierge_reply`) não contam — ela pode trocar 50 mensagens com o cliente sem restrição.

## 11. Fases do MVP

### Fase A — Infraestrutura base

- Migrations: 3 tabelas novas + 2 colunas em `captain_units`
- Models: `Captain::Lifecycle::Rule`, `Captain::Lifecycle::Delivery`, `Captain::Lifecycle::Config`
- Event scheduler: listener do `Captain::Reservation` lifecycle, enfileira `LifecycleDispatcherJob`
- Dispatcher job: pipeline de guards + render Liquid + envio via inbox
- Extensão do `Wuzapi::Client`: `send_buttons`, `send_list`, `send_url_button`
- Extensão do `Whatsapp::Providers::WuzapiService`: wiring dos novos métodos

### Fase B — UI

- Rota nova "Jornada do Cliente" no menu Captain
- Tab Regras: lista + wizard de 4 passos + templates prontos
- Tab Configurações: guards + Sofia por unidade
- Tab Histórico: paginada + modal de preview
- Editor de mensagem com autocomplete + tooltip + botão preview

### Fase C — Sofia

- Tipo/flag de `Captain::Assistant` concierge
- Liquid render context pra `concierge.*`, injeção via `{% render 'concierge' %}`
- Template inicial sugerido
- Dispatcher setando `current_unit_id` em `conversation.custom_attributes`
- Tools `handoff` e `add_label_to_conversation` já existem no catálogo, só garantir que aparecem pra Sofia

### Fase D — QA e rollout piloto

- Teste end-to-end com 1 unidade real (Prime Águas Lindas)
- Monitoramento: envios, taxa de sucesso, reclamações, fila Sidekiq
- Ajustes finos antes de liberar pras outras unidades

## 12. Testes

### 12.1. Unit

- Cada guard isolado: quiet hours (Opção C), max-5, opt-out label, intervalo mínimo, customer replied
- Resolver de `fire_at` pra cada evento × direção de offset
- Liquid render com contexto completo
- Rate limit de variáveis inválidas / chaves faltando
- Validação de filtros (match positivo e negativo)

### 12.2. Integração

- Pipeline completa do dispatcher (schedule → fire → guards → render → send → log)
- Event flow: reserva criada → job enfileirado; cancelada → deliveries viram cancelled; regra editada → recompilação
- Race conditions: 2 regras disparando simultaneamente respeitam cap de 5 (optimistic lock)
- WuzAPI stubbed pra `send_buttons/list/url_button` retornando sucesso/falha

### 12.3. End-to-end manual

- Criar regra pela UI, criar reserva de teste, aguardar `fire_at`, verificar mensagem chegando em número real
- Cancelar reserva após agendamento, verificar que mensagens pendentes não saem
- Editar regra, verificar que reservas futuras recompilam

## 13. Observabilidade

- Log estruturado por etapa do dispatcher (`rule_id`, `delivery_id`, `skip_reason`, `elapsed_ms`)
- Métricas Prometheus:
  - `lifecycle_deliveries_total{rule_id, status}` — counter
  - `lifecycle_dispatch_duration_seconds` — histogram
  - `lifecycle_skip_reasons_total{reason}` — counter
- Alertas:
  - Taxa de `failed` > 5% (erro no WuzAPI ou rule config quebrada)
  - Spike de `skipped` com motivo `max_reached` (possível loop de config)
  - Job com mais de 5min de delay entre `fire_at` e `sent_at`

## 14. Fora de escopo do MVP

Itens deferidos pra fase 2+ (salvos também em `Obsidian Vault/Ideias/Lifecycle Automation/backlog.md`):

- **Detecção heurística de `checkin.detected` / `checkout.detected`** — cruzar categoria reservada + unidades ocupadas pra inferir entrada real
- **A/B testing de mensagens** — 50% recebem versão A, 50% versão B, compara métricas
- **Dashboard analítico de funil** — taxa de resposta, conversão de review, NPS agregado
- **Integração com Google Reviews API** — validar review deixado antes de disparar brinde
- **Multi-idioma** — templates em inglês/espanhol pra hóspedes gringos
- **Mensagens com mídia rica** — imagens, vídeos, PDFs no cardápio
- **Cenários múltiplos pra Sofia** — se uma persona crescer e precisar ramificar
- **Memória de longo prazo do cliente** — "sua terceira estadia com a gente!"
- **Integração Wi-Fi do hotel** — mensagem automática com senha ao detectar entrada
- **Override de guards por unidade** — hoje é só por conta

## 15. Riscos conhecidos

1. **Ban do número WhatsApp concierge** — mesmo com guards, volume alto pode acionar anti-spam da Meta. **Mitigação:** rollout gradual por unidade, aquecimento do número novo antes de ligar regras em massa, monitorar taxa de bloqueio via `skip_reason=failed`.

2. **LLM alucinando info errada sobre o hotel** — se `concierge_config.knowledge` estiver mal escrito ou incompleto, Sofia inventa. **Mitigação:** botão preview no editor, teste manual com perguntas difíceis antes de ativar, histórico de conversas da Sofia revisado semanalmente no rollout piloto.

3. **Liquid inseguro / template injection** — template malicioso no `message_body` pode vazar dado. **Mitigação:** usar Liquid strict mode como o Chatwoot Captain já faz, whitelist de filters permitidos, validação no save da regra.

4. **Race conditions no cap de 5** — 2 regras disparando simultaneamente, contador desatualizado. **Mitigação:** optimistic lock no counter, re-check dentro da transação do dispatcher.

5. **Mudança de `check_in_at` sem reagendar** — bug de regra que não escuta o `after_update` deixaria mensagens saindo no horário antigo. **Mitigação:** teste de integração obrigatório cobrindo esse caso.

6. **Volume explosivo de deliveries** — conta com 100 regras × 1000 reservas/dia = 100k linhas/dia na `deliveries`. **Mitigação:** retenção de 180 dias com job noturno, índices corretos, sanity check no wizard mostrando quantas reservas serão afetadas.

7. **Sofia respondendo com conhecimento errado** — bug na injeção do `current_unit_id` faria Sofia usar knowledge da unidade A pra cliente da B. **Mitigação:** teste explícito cobrindo multi-unit em mesmo inbox; assertions no dispatcher garantindo que `current_unit_id` foi setado antes de chamar `MessageBuilder`.
