# Jornada do Cliente — Backend Handoff (pra sessão nova)

**Data:** 2026-04-15
**Status:** Backend (Fases A + C do spec) 100% entregue. UI (Fase B) ainda não — próximo plano.

## Pra retomar numa sessão nova

Colar este prompt no início da sessão:

> Quero escrever o plano de implementação da Fase B — a UI "Jornada do Cliente" — do spec em `docs/superpowers/specs/2026-04-15-jornada-do-cliente-design.md` seção 9. O backend já está pronto (ver `docs/superpowers/plans/2026-04-15-jornada-do-cliente-backend.md` e o handoff em `docs/superpowers/plans/2026-04-15-jornada-do-cliente-backend-handoff.md`). Chama a skill writing-plans.

## O que está pronto (commits no main)

21 commits atômicos entre `1c89ef73f` e `325f05c3e`. Todos verdes, ~120 specs, 0 regressões, Rubocop limpo.

Mapa lógico:

| Camada | Arquivo principal | Papel |
|---|---|---|
| **Schema** | `db/migrate/20260415040927_*.rb` + `20260415040957_*.rb` | 3 tabelas `captain_lifecycle_*` + 2 colunas em `captain_units` |
| **Model: Config** | `enterprise/app/models/captain/lifecycle/config.rb` | Singleton por conta. Guards configuráveis. `.for_account(account)` helper |
| **Model: Rule** | `enterprise/app/models/captain/lifecycle/rule.rb` | `EVENTS` constant, `MESSAGE_TYPES`, `#matches_reservation?` com 3 filtros |
| **Model: Delivery** | `enterprise/app/models/captain/lifecycle/delivery.rb` | Audit log. `mark_sent!/skipped!/cancelled!/failed!`, `.count_sent_for_reservation(id)` |
| **Model ext** | `enterprise/app/models/captain/unit.rb` | `concierge_persona_name` (default Sofia), `concierge_knowledge`, `concierge_variables`, `concierge_configured?`, `belongs_to :concierge_inbox` |
| **Model ext** | `enterprise/app/models/captain/reservation.rb` | 3 hooks: `after_create_commit :schedule_lifecycle_rules`, `after_update_commit :handle_lifecycle_status_change` (on `saved_change_to_status?` + status in cancelled/no_show), `after_update_commit :handle_lifecycle_checkin_change` (on `saved_change_to_check_in_at?`). Todos com `rescue StandardError` pra nunca derrubar a reserva |
| **Service: EventResolver** | `enterprise/app/services/captain/lifecycle/event_resolver.rb` | `.resolve(reservation, event)` → timestamp. `checkin.detected`/`checkout.detected` retornam nil (unsupported no MVP) |
| **Service: Scheduler** | `enterprise/app/services/captain/lifecycle/scheduler.rb` | `.schedule_for(reservation)`, `.cancel_pending(reservation)`, `.reschedule_for_checkin_change(reservation)` — cria deliveries + enqueue Sidekiq |
| **Service: ContextBuilder** | `enterprise/app/services/captain/lifecycle/context_builder.rb` | `.build(reservation)` → `{ 'customer' => {...}, 'reservation' => {...}, 'hotel' => {...} }` |
| **Guards** | `enterprise/app/services/captain/lifecycle/guards/*.rb` | Base + 6 guards: ReservationActive, OptOutLabel, MaxPerReservation (CAP=5), QuietHours (Opção C 2h), MinInterval, CustomerReplied |
| **Service: Dispatcher** | `enterprise/app/services/captain/lifecycle/dispatcher.rb` | Pipeline: `call` → guards → render → `send_message` → `mark_sent!`. Order matters, stop on first non-pass |
| **Job** | `enterprise/app/jobs/captain/lifecycle/dispatcher_job.rb` | `perform(delivery_id)` chama Dispatcher. `self.perform_at(time, id)` delega pra `set(wait_until:).perform_later` |
| **Liquid** | `enterprise/app/models/concerns/agentable.rb` | `render_orchestrator_prompt` agora injeta `concierge:` e `reservation:` no enhanced_context, resolvidos a partir de `conversation.custom_attributes['current_unit_id']` |
| **Liquid templates** | `enterprise/lib/captain/prompts/concierge.liquid` + `snippets/concierge.liquid` | Template padrão da Sofia (o dono reescreve) |
| **WuzAPI** | `app/services/wuzapi/client.rb` | `send_buttons`, `send_list`, `send_url_button` |
| **WuzAPI provider** | `app/services/whatsapp/providers/wuzapi_service.rb` | `send_interactive_message(phone, payload)` roteia por `type` |
| **Seed** | `db/seeds/captain_lifecycle_demo.rb` | Smoke test via `bundle exec rails runner` |

## Gotchas descobertos durante a implementação (IMPORTANTE — não repetir)

Estas armadilhas custaram tempo nos subagentes — documento aqui pra próxima sessão não tropeçar:

### 1. `Captain::Reservation` associa `unit`, não `captain_unit`

A coluna é `captain_unit_id` mas a associação é `belongs_to :unit, class_name: 'Captain::Unit', foreign_key: 'captain_unit_id'`. Então no factory e nos testes é **`unit: unit`**, não `captain_unit: unit`. Cuidado com copy-paste de código do spec.

### 2. Factory `:captain_unit` foi consertada em `325f05c3e`

Antes, `association :brand, account: account` era quebrado (FactoryBot não avalia `account` lazily nessa forma). Fix aplicado: bloco `brand do ... end` que busca/cria brand na mesma conta. **Agora funciona:** `create(:captain_unit)` e `create(:captain_unit, account: some_account)` são idiomáticos de novo. Todos os specs do lifecycle usaram workaround `Captain::Unit.create!(account:, brand:, name:)` porque o bug existia quando foram escritos — não são wrong, só não-idiomáticos. Não precisa refatorar.

### 3. Factory `:captain_reservation` foi criada na T3

Estava ausente do repo antes desta feature. Criada em `spec/factories/captain/reservation.rb` com `unit { nil }` default. Qualquer spec que precise de reserva com unit específica deve passar `unit: unit`.

### 4. `Wuzapi::Client#request` retorna `Hash`, não `Faraday::Response`

O cliente tem `handle_response` interno que parseia o body. Então `client.send_buttons(...)` retorna um hash, não uma response. Tests não podem usar `be_success` — usam `be_a(Hash)` ou testam chaves do hash retornado.

### 5. `perform_at` não é nativo do ActiveJob (só Sidekiq)

A T9 reimplementou como class method em `DispatcherJob`:

```ruby
def self.perform_at(wait_until, delivery_id)
  set(wait_until: wait_until).perform_later(delivery_id)
end
```

Isso é a forma idiomática do ActiveJob pra agendar. Scheduler e Dispatcher chamam via `Captain::Lifecycle::DispatcherJob.perform_at(fire_at, delivery_id)`.

### 6. `belongs_to :conversation` / `belongs_to :message` precisam de `class_name: '::Conversation'`

Rails autoload resolve `Conversation` dentro de `Captain::Lifecycle::Delivery` como `Captain::Lifecycle::Conversation` (inexistente), causando `ArgumentError` em runtime. A T14 consertou em `delivery.rb`. Mesma gotcha vale pra qualquer model novo dentro do namespace `Captain::Lifecycle::*` que referencie modelos top-level.

### 7. `build_stubbed` falha com FK constraints

No Dispatcher spec (T15), `mark_sent!` persiste `conversation_id` e `message_id`. Stubs feitos com `build_stubbed` quebram na constraint. Solução: usa `create(:conversation)` + `create(:message)` reais no before block, mesmo quando a intenção é só stub.

### 8. Lifecycle hook pode criar deliveries "fantasmas" em specs de outros models

Todo `create(:captain_reservation)` agora dispara `after_create_commit :schedule_lifecycle_rules` → Scheduler roda → se houver rules na DB, cria deliveries. Specs que contam deliveries precisam ou (a) criar reservation ANTES das rules, ou (b) stubar `Captain::Lifecycle::Scheduler.schedule_for`. A T9 e T14 já ajustaram os specs afetados, mas **qualquer spec novo que instancia reserva + conta deliveries precisa lembrar disso.**

### 9. `captain_unit` tem campo `brand_id` obrigatório — não `captain_brand_id`

A coluna é nomeada assim, diferente da tabela (`captain_brands`). Testes que criam unit precisam passar `brand:` (nome da associação), não `captain_brand:`.

## Specs — onde estão e como rodar

Suite completa do lifecycle:

```bash
eval "$(rbenv init - zsh)" && rbenv shell 3.4.4 && bundle exec rspec \
  spec/enterprise/models/captain/lifecycle \
  spec/enterprise/services/captain/lifecycle \
  spec/enterprise/jobs/captain/lifecycle \
  spec/enterprise/integration/captain \
  spec/enterprise/models/captain/reservation_lifecycle_hooks_spec.rb \
  spec/enterprise/models/captain/unit_concierge_accessors_spec.rb \
  spec/enterprise/models/concerns/agentable_concierge_spec.rb \
  spec/services/wuzapi/client_interactive_spec.rb \
  spec/services/whatsapp/providers/wuzapi_interactive_spec.rb \
  spec/factories/captain_unit_factory_spec.rb
```

Esperado no check final: **~120 examples, 0 failures, 0 pending.** Tempo total ~8s.

Regression gate (specs de modelos pré-existentes que foram tocados):

```bash
bundle exec rspec spec/enterprise/models/captain/reservation_spec.rb
```

## O que NÃO foi implementado (e por quê)

### Fora de escopo deste plano (estão no spec, fase 2+)

- **Detecção heurística de `checkin.detected` / `checkout.detected`** — os eventos existem na enum, mas `EventResolver` retorna `nil`, ou seja, rules com esses eventos nunca disparam. Deferido pro backlog (`Ideias/Lifecycle Automation/backlog.md`)
- **Dashboard analítico / métricas Prometheus** — logs estruturados sim, Prometheus não. Deferido
- **Retention job (purge de deliveries >180 dias)** — design no spec, não implementado. Pode virar uma task de 10min depois
- **Cron de 1-em-1-min pra destravar mensagens adiadas por quiet hours** — não necessário no MVP porque quiet hours é default false. Se algum cliente ligar, re-avaliar

### Próximo plano (Fase B — UI)

Seção 9 do spec. Três tabs dentro de uma aba nova "Jornada do Cliente" no menu Captain:

- **Regras** — lista + wizard de 4 passos + templates prontos + editor de mensagem com autocomplete
- **Configurações** — guards + Sofia por unidade (inbox, persona_name, knowledge textarea, variables key/value)
- **Histórico** — lista da `captain_lifecycle_deliveries` com preview modal do `rendered_body`

Estimativa: 15-20 tasks Vue 3 + Pinia + rotas Rails/jbuilder. Multilíngue pt_BR + en obrigatório. Vai precisar de endpoints REST que ainda não existem (CRUD de rules, update de config, GET de deliveries, GET/PATCH de concierge_config em captain_units).

## Como testar manualmente agora (sem UI)

Via console Rails (precisa ter `Account.first` + `Captain::Unit` + `Inbox`):

```ruby
# Console
account = Account.first
unit = account.captain_units.first
inbox = unit.inboxes.first || Inbox.first

unit.update!(
  concierge_inbox_id: inbox.id,
  concierge_config: {
    'persona_name' => 'Sofia',
    'knowledge' => '# Sobre\nHotel teste.\n',
    'variables' => { 'wifi_password' => 'teste123', 'menu_link' => 'https://menu.x' }
  }
)

rule = Captain::Lifecycle::Rule.create!(
  account: account,
  name: 'Demo pré check-in',
  event: 'checkin.scheduled_at',
  offset_minutes: -10,
  message_body: 'Oi {{ customer.first_name }}! Wifi: {{ hotel.wifi_password }}'
)

# Agora cria uma reserva — delivery é agendada automaticamente via hook
contact = account.contacts.first || Contact.create!(account: account, name: 'Teste', phone_number: '+5561900000000')
reservation = Captain::Reservation.create!(
  account: account,
  unit: unit,
  contact: contact,
  suite_identifier: 'Alexa',
  status: :scheduled,
  total_amount: 160,
  check_in_at: 20.minutes.from_now,
  check_out_at: 8.hours.from_now,
  inbox: inbox
)

# Ver a delivery agendada
delivery = Captain::Lifecycle::Delivery.where(captain_reservation_id: reservation.id).last
puts "Delivery ##{delivery.id} status=#{delivery.status} fire_at=#{delivery.fire_at}"

# Disparar manual (sem esperar fire_at)
Captain::Lifecycle::DispatcherJob.perform_now(delivery.id)

# Checar resultado
delivery.reload
puts "Status: #{delivery.status}"
puts "Rendered: #{delivery.rendered_body}"
puts "Skip reason: #{delivery.skip_reason}" if delivery.status == 'skipped'
```

Ou via seed:

```bash
eval "$(rbenv init - zsh)" && rbenv shell 3.4.4 && bundle exec rails runner db/seeds/captain_lifecycle_demo.rb
```

## Arquivos e pastas relevantes (resumo de ponteiros)

- **Spec de design:** `docs/superpowers/specs/2026-04-15-jornada-do-cliente-design.md`
- **Plano backend:** `docs/superpowers/plans/2026-04-15-jornada-do-cliente-backend.md`
- **Backlog de ideias:** `/Users/user/Documents/Obsidian Vault/Ideias/Lifecycle Automation/backlog.md`
- **Docs Captain prompts (Jasmine):** `/Users/user/Documents/Obsidian Vault/Dev/Prompts/Captain Chatwoot/`
- **Models:** `enterprise/app/models/captain/lifecycle/`
- **Services:** `enterprise/app/services/captain/lifecycle/`
- **Jobs:** `enterprise/app/jobs/captain/lifecycle/`
- **Specs:** `spec/enterprise/*/captain/lifecycle/` + `spec/enterprise/integration/captain/lifecycle_flow_spec.rb`
