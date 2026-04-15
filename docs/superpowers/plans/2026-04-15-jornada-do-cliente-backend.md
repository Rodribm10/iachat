# Jornada do Cliente — Backend (Fases A + C) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the complete backend of Jornada do Cliente — lifecycle rule engine, scheduler, dispatcher pipeline with anti-ban guards, interactive-message support in WuzAPI, and the concierge AI (Sofia) wiring. Produces a headless but fully functional system that can be exercised via Rails console / API before the admin UI (Fase B) is built.

**Architecture:** Event-driven scheduler enfileira `LifecycleDispatcherJob` no Sidekiq com `perform_at(fire_at, delivery_id)`. Guards checam no runtime antes de enviar via WuzAPI. Sofia é um `Captain::Assistant` com orchestrator prompt Liquid que injeta `{{ concierge.* }}` dinamicamente baseado em `conversation.custom_attributes['current_unit_id']`.

**Tech Stack:**
- Rails 7.1 + PostgreSQL + Sidekiq + Wisper
- `Captain::PromptRenderer` (Liquid) já existente
- WuzAPI via `Wuzapi::Client` + `Whatsapp::Providers::WuzapiService`
- RSpec + FactoryBot + WebMock

**Spec:** `docs/superpowers/specs/2026-04-15-jornada-do-cliente-design.md`

**Out of scope (this plan):**
- Admin UI (Fase B — nova aba "Jornada do Cliente", wizard, histórico, editor) — será outro plano
- Detecção heurística de `checkin.detected`/`checkout.detected` (fase 2+)
- Dashboard analítico e métricas Prometheus (fase 2+)
- Multi-idioma

---

## File Structure

### Novos arquivos (models + migrations)

- `db/migrate/YYYYMMDDHHMMSS_create_captain_lifecycle_tables.rb` — 3 tabelas novas
- `db/migrate/YYYYMMDDHHMMSS_add_concierge_to_captain_units.rb` — 2 colunas em `captain_units`
- `enterprise/app/models/captain/lifecycle/rule.rb`
- `enterprise/app/models/captain/lifecycle/delivery.rb`
- `enterprise/app/models/captain/lifecycle/config.rb`

### Serviços e jobs

- `enterprise/app/services/captain/lifecycle/event_resolver.rb` — resolve evento → timestamp
- `enterprise/app/services/captain/lifecycle/rule_matcher.rb` — encontra regras que batem com uma reserva num evento
- `enterprise/app/services/captain/lifecycle/scheduler.rb` — orquestra schedule/cancel/reschedule
- `enterprise/app/services/captain/lifecycle/context_builder.rb` — monta hash de variáveis (customer, reservation, hotel) pro Liquid
- `enterprise/app/services/captain/lifecycle/dispatcher.rb` — pipeline com guards, render e send
- `enterprise/app/services/captain/lifecycle/guards/base.rb`
- `enterprise/app/services/captain/lifecycle/guards/reservation_active.rb`
- `enterprise/app/services/captain/lifecycle/guards/opt_out_label.rb`
- `enterprise/app/services/captain/lifecycle/guards/max_per_reservation.rb`
- `enterprise/app/services/captain/lifecycle/guards/quiet_hours.rb`
- `enterprise/app/services/captain/lifecycle/guards/min_interval.rb`
- `enterprise/app/services/captain/lifecycle/guards/customer_replied.rb`
- `enterprise/app/jobs/captain/lifecycle/dispatcher_job.rb`

### Extensões de código existente

- `enterprise/app/models/captain/unit.rb` — accessors pra `concierge_config` jsonb
- `enterprise/app/models/captain/reservation.rb` — hooks `after_commit` / `after_update` chamando scheduler
- `enterprise/app/models/concerns/agentable.rb` — injeção de `concierge` no enhanced_context
- `enterprise/lib/captain/prompts/concierge.liquid` — template padrão da Sofia
- `app/services/wuzapi/client.rb` — `send_buttons`, `send_list`, `send_url_button`
- `app/services/whatsapp/providers/wuzapi_service.rb` — dispatch de mensagens interativas

### Specs

- `spec/enterprise/models/captain/lifecycle/rule_spec.rb`
- `spec/enterprise/models/captain/lifecycle/delivery_spec.rb`
- `spec/enterprise/models/captain/lifecycle/config_spec.rb`
- `spec/enterprise/services/captain/lifecycle/event_resolver_spec.rb`
- `spec/enterprise/services/captain/lifecycle/rule_matcher_spec.rb`
- `spec/enterprise/services/captain/lifecycle/scheduler_spec.rb`
- `spec/enterprise/services/captain/lifecycle/context_builder_spec.rb`
- `spec/enterprise/services/captain/lifecycle/dispatcher_spec.rb`
- `spec/enterprise/services/captain/lifecycle/guards/*_spec.rb`
- `spec/enterprise/jobs/captain/lifecycle/dispatcher_job_spec.rb`
- `spec/enterprise/integration/captain/lifecycle_flow_spec.rb`

### Factories

- `spec/factories/captain_lifecycle_rules.rb`
- `spec/factories/captain_lifecycle_deliveries.rb`
- `spec/factories/captain_lifecycle_configs.rb`

---

## Task 1: Migrations for lifecycle tables

**Files:**
- Create: `db/migrate/<TIMESTAMP>_create_captain_lifecycle_tables.rb`
- Create: `db/migrate/<TIMESTAMP2>_add_concierge_to_captain_units.rb`

- [ ] **Step 1: Generate migration 1 — lifecycle tables**

Run: `bundle exec bin/rails generate migration CreateCaptainLifecycleTables`

- [ ] **Step 2: Write migration 1**

Replace the generated file with:

```ruby
class CreateCaptainLifecycleTables < ActiveRecord::Migration[7.1]
  def change
    create_table :captain_lifecycle_rules do |t|
      t.references :account, null: false, foreign_key: true, index: true
      t.string :name, null: false
      t.text :description
      t.boolean :enabled, null: false, default: true
      t.string :event, null: false
      t.integer :offset_minutes, null: false, default: 0
      t.jsonb :filters, null: false, default: {}
      t.string :message_type, null: false, default: 'text'
      t.text :message_body, null: false
      t.jsonb :message_payload
      t.integer :priority, null: false, default: 50
      t.references :created_by_user, foreign_key: { to_table: :users }, index: true
      t.timestamps
    end
    add_index :captain_lifecycle_rules, %i[account_id enabled event]

    create_table :captain_lifecycle_deliveries do |t|
      t.references :account, null: false, foreign_key: true, index: true
      t.references :lifecycle_rule,
                   foreign_key: { to_table: :captain_lifecycle_rules },
                   index: { name: 'idx_lifecycle_deliveries_rule' }
      t.references :captain_reservation,
                   null: false,
                   foreign_key: true,
                   index: { name: 'idx_lifecycle_deliveries_reservation' }
      t.references :conversation, foreign_key: true
      t.references :message, foreign_key: true
      t.references :inbox, foreign_key: true
      t.datetime :fire_at, null: false
      t.datetime :sent_at
      t.string :status, null: false, default: 'scheduled'
      t.string :skip_reason
      t.text :failure_reason
      t.text :rendered_body
      t.string :origin, null: false, default: 'scheduled_lifecycle'
      t.timestamps
    end
    add_index :captain_lifecycle_deliveries,
              %i[captain_reservation_id origin status],
              name: 'idx_lifecycle_deliveries_cap_check'
    add_index :captain_lifecycle_deliveries,
              %i[account_id status fire_at],
              name: 'idx_lifecycle_deliveries_dashboard'
    add_index :captain_lifecycle_deliveries,
              :fire_at,
              where: "status = 'scheduled'",
              name: 'idx_lifecycle_deliveries_scheduled'

    create_table :captain_lifecycle_configs do |t|
      t.references :account, null: false, foreign_key: true, index: { unique: true }
      t.boolean :quiet_hours_enabled, null: false, default: false
      t.time :quiet_hours_from, null: false, default: '23:00'
      t.time :quiet_hours_to, null: false, default: '08:00'
      t.integer :min_interval_minutes, null: false, default: 30
      t.boolean :pause_on_customer_reply, null: false, default: false
      t.integer :pause_on_customer_reply_within_minutes, null: false, default: 60
      t.references :opt_out_label, foreign_key: { to_table: :labels }
      t.timestamps
    end
  end
end
```

- [ ] **Step 3: Generate migration 2 — captain_units extensions**

Run: `bundle exec bin/rails generate migration AddConciergeToCaptainUnits`

- [ ] **Step 4: Write migration 2**

```ruby
class AddConciergeToCaptainUnits < ActiveRecord::Migration[7.1]
  def change
    add_reference :captain_units, :concierge_inbox,
                  foreign_key: { to_table: :inboxes },
                  null: true
    add_column :captain_units, :concierge_config, :jsonb, null: false, default: {}
  end
end
```

- [ ] **Step 5: Run migrations**

Run: `bundle exec bin/rails db:migrate`
Expected: both migrations apply, no errors.

- [ ] **Step 6: Verify schema**

Run: `bundle exec bin/rails runner 'puts ActiveRecord::Base.connection.tables.grep(/lifecycle/).sort'`
Expected output:
```
captain_lifecycle_configs
captain_lifecycle_deliveries
captain_lifecycle_rules
```

Run: `bundle exec bin/rails runner 'puts Captain::Unit.column_names.grep(/concierge/).sort'`
Expected output:
```
concierge_config
concierge_inbox_id
```

- [ ] **Step 7: Commit**

```bash
git add db/migrate/*lifecycle* db/migrate/*concierge* db/schema.rb
git commit -m "feat(lifecycle): add captain_lifecycle_* tables and concierge columns on captain_units"
```

---

## Task 2: Captain::Lifecycle::Config model

Config is the smallest of the three models (account-wide singleton). Do it first to establish the module pattern.

**Files:**
- Create: `enterprise/app/models/captain/lifecycle.rb` (namespace module)
- Create: `enterprise/app/models/captain/lifecycle/config.rb`
- Create: `spec/enterprise/models/captain/lifecycle/config_spec.rb`
- Create: `spec/factories/captain_lifecycle_configs.rb`

- [ ] **Step 1: Write failing spec**

```ruby
# spec/enterprise/models/captain/lifecycle/config_spec.rb
require 'rails_helper'

RSpec.describe Captain::Lifecycle::Config, type: :model do
  describe 'associations' do
    it { is_expected.to belong_to(:account) }
    it { is_expected.to belong_to(:opt_out_label).class_name('Label').optional }
  end

  describe 'validations' do
    subject { build(:captain_lifecycle_config) }

    it { is_expected.to validate_uniqueness_of(:account_id) }
    it { is_expected.to validate_numericality_of(:min_interval_minutes).is_greater_than_or_equal_to(0) }
    it { is_expected.to validate_numericality_of(:pause_on_customer_reply_within_minutes).is_greater_than_or_equal_to(0) }
  end

  describe '.for_account' do
    let(:account) { create(:account) }

    it 'returns existing config when present' do
      config = create(:captain_lifecycle_config, account: account)
      expect(described_class.for_account(account)).to eq(config)
    end

    it 'creates default config when missing' do
      expect { described_class.for_account(account) }
        .to change(described_class, :count).by(1)
    end

    it 'defaults have quiet_hours disabled' do
      config = described_class.for_account(account)
      expect(config.quiet_hours_enabled).to be(false)
    end
  end
end
```

- [ ] **Step 2: Write the factory**

```ruby
# spec/factories/captain_lifecycle_configs.rb
FactoryBot.define do
  factory :captain_lifecycle_config, class: 'Captain::Lifecycle::Config' do
    account
    quiet_hours_enabled { false }
    quiet_hours_from { '23:00' }
    quiet_hours_to { '08:00' }
    min_interval_minutes { 30 }
    pause_on_customer_reply { false }
    pause_on_customer_reply_within_minutes { 60 }
  end
end
```

- [ ] **Step 3: Run spec to verify failure**

Run: `bundle exec rspec spec/enterprise/models/captain/lifecycle/config_spec.rb`
Expected: FAIL — `uninitialized constant Captain::Lifecycle` (or `Config`).

- [ ] **Step 4: Create namespace module**

```ruby
# enterprise/app/models/captain/lifecycle.rb
module Captain
  module Lifecycle
  end
end
```

- [ ] **Step 5: Create Config model**

```ruby
# enterprise/app/models/captain/lifecycle/config.rb
class Captain::Lifecycle::Config < ApplicationRecord
  self.table_name = 'captain_lifecycle_configs'

  belongs_to :account
  belongs_to :opt_out_label, class_name: 'Label', optional: true

  validates :account_id, uniqueness: true
  validates :min_interval_minutes, numericality: { greater_than_or_equal_to: 0 }
  validates :pause_on_customer_reply_within_minutes, numericality: { greater_than_or_equal_to: 0 }

  def self.for_account(account)
    find_or_create_by!(account_id: account.id)
  end
end
```

- [ ] **Step 6: Run spec to verify pass**

Run: `bundle exec rspec spec/enterprise/models/captain/lifecycle/config_spec.rb`
Expected: all examples pass.

- [ ] **Step 7: Commit**

```bash
git add enterprise/app/models/captain/lifecycle.rb enterprise/app/models/captain/lifecycle/config.rb spec/enterprise/models/captain/lifecycle/config_spec.rb spec/factories/captain_lifecycle_configs.rb
git commit -m "feat(lifecycle): add Captain::Lifecycle::Config model"
```

---

## Task 3: Captain::Lifecycle::Rule model

**Files:**
- Create: `enterprise/app/models/captain/lifecycle/rule.rb`
- Create: `spec/enterprise/models/captain/lifecycle/rule_spec.rb`
- Create: `spec/factories/captain_lifecycle_rules.rb`

- [ ] **Step 1: Write failing spec**

```ruby
# spec/enterprise/models/captain/lifecycle/rule_spec.rb
require 'rails_helper'

RSpec.describe Captain::Lifecycle::Rule, type: :model do
  describe 'associations' do
    it { is_expected.to belong_to(:account) }
    it { is_expected.to belong_to(:created_by_user).class_name('User').optional }
  end

  describe 'validations' do
    subject { build(:captain_lifecycle_rule) }

    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:event) }
    it { is_expected.to validate_presence_of(:message_body) }
    it { is_expected.to validate_inclusion_of(:event).in_array(Captain::Lifecycle::Rule::EVENTS) }
    it { is_expected.to validate_inclusion_of(:message_type).in_array(%w[text buttons list url_button]) }
  end

  describe '.active' do
    it 'returns only enabled rules' do
      enabled = create(:captain_lifecycle_rule, enabled: true)
      create(:captain_lifecycle_rule, enabled: false)
      expect(described_class.active).to contain_exactly(enabled)
    end
  end

  describe '.for_event' do
    it 'filters by event' do
      rule = create(:captain_lifecycle_rule, event: 'checkin.scheduled_at')
      create(:captain_lifecycle_rule, event: 'reservation.confirmed')
      expect(described_class.for_event('checkin.scheduled_at')).to contain_exactly(rule)
    end
  end

  describe '#matches_reservation?' do
    let(:account) { create(:account) }
    let(:unit) { create(:captain_unit, account: account, name: 'Águas Lindas') }
    let(:reservation) do
      create(:captain_reservation,
             account: account,
             captain_unit: unit,
             suite_identifier: 'Alexa',
             metadata: { 'permanencia' => 'Pernoite' })
    end

    it 'matches when all filters empty' do
      rule = build(:captain_lifecycle_rule, account: account, filters: {})
      expect(rule.matches_reservation?(reservation)).to be(true)
    end

    it 'matches when unit_id in filter' do
      rule = build(:captain_lifecycle_rule, account: account, filters: { 'unit_ids' => [unit.id] })
      expect(rule.matches_reservation?(reservation)).to be(true)
    end

    it 'does not match when unit_id not in filter' do
      rule = build(:captain_lifecycle_rule, account: account, filters: { 'unit_ids' => [999] })
      expect(rule.matches_reservation?(reservation)).to be(false)
    end

    it 'matches when categoria in filter' do
      rule = build(:captain_lifecycle_rule, account: account, filters: { 'categorias' => ['Alexa'] })
      expect(rule.matches_reservation?(reservation)).to be(true)
    end

    it 'does not match when categoria not in filter' do
      rule = build(:captain_lifecycle_rule, account: account, filters: { 'categorias' => ['Stilo'] })
      expect(rule.matches_reservation?(reservation)).to be(false)
    end

    it 'matches when permanencia in filter' do
      rule = build(:captain_lifecycle_rule, account: account, filters: { 'permanencias' => ['Pernoite'] })
      expect(rule.matches_reservation?(reservation)).to be(true)
    end

    it 'requires all specified filters to match' do
      rule = build(:captain_lifecycle_rule, account: account,
                                             filters: { 'unit_ids' => [unit.id], 'categorias' => ['Stilo'] })
      expect(rule.matches_reservation?(reservation)).to be(false)
    end
  end
end
```

- [ ] **Step 2: Write factory**

```ruby
# spec/factories/captain_lifecycle_rules.rb
FactoryBot.define do
  factory :captain_lifecycle_rule, class: 'Captain::Lifecycle::Rule' do
    account
    sequence(:name) { |n| "Rule ##{n}" }
    enabled { true }
    event { 'checkin.scheduled_at' }
    offset_minutes { -10 }
    filters { {} }
    message_type { 'text' }
    message_body { 'Olá {{ customer.first_name }}, sua suíte {{ reservation.suite }} está pronta!' }
    priority { 50 }
  end
end
```

- [ ] **Step 3: Run spec to verify failure**

Run: `bundle exec rspec spec/enterprise/models/captain/lifecycle/rule_spec.rb`
Expected: FAIL — `uninitialized constant Captain::Lifecycle::Rule`.

- [ ] **Step 4: Write the model**

```ruby
# enterprise/app/models/captain/lifecycle/rule.rb
class Captain::Lifecycle::Rule < ApplicationRecord
  self.table_name = 'captain_lifecycle_rules'

  EVENTS = %w[
    reservation.confirmed
    checkin.scheduled_at
    checkin.detected
    checkout.scheduled_at
    checkout.detected
    reservation.cancelled
    reservation.no_show
  ].freeze

  MESSAGE_TYPES = %w[text buttons list url_button].freeze

  belongs_to :account
  belongs_to :created_by_user, class_name: 'User', optional: true

  validates :name, presence: true
  validates :event, presence: true, inclusion: { in: EVENTS }
  validates :message_body, presence: true
  validates :message_type, inclusion: { in: MESSAGE_TYPES }

  scope :active, -> { where(enabled: true) }
  scope :for_event, ->(event) { where(event: event) }

  def matches_reservation?(reservation)
    return false unless reservation

    filters_hash = filters.presence || {}
    matches_unit?(filters_hash, reservation) &&
      matches_categoria?(filters_hash, reservation) &&
      matches_permanencia?(filters_hash, reservation)
  end

  private

  def matches_unit?(filters_hash, reservation)
    unit_ids = Array(filters_hash['unit_ids'])
    return true if unit_ids.empty?

    unit_ids.include?(reservation.captain_unit_id)
  end

  def matches_categoria?(filters_hash, reservation)
    categorias = Array(filters_hash['categorias'])
    return true if categorias.empty?

    categorias.include?(reservation.suite_identifier)
  end

  def matches_permanencia?(filters_hash, reservation)
    permanencias = Array(filters_hash['permanencias'])
    return true if permanencias.empty?

    actual = reservation.metadata.to_h['permanencia']
    permanencias.include?(actual)
  end
end
```

- [ ] **Step 5: Run spec to verify pass**

Run: `bundle exec rspec spec/enterprise/models/captain/lifecycle/rule_spec.rb`
Expected: all examples pass.

- [ ] **Step 6: Commit**

```bash
git add enterprise/app/models/captain/lifecycle/rule.rb spec/enterprise/models/captain/lifecycle/rule_spec.rb spec/factories/captain_lifecycle_rules.rb
git commit -m "feat(lifecycle): add Captain::Lifecycle::Rule model with filter matching"
```

---

## Task 4: Captain::Lifecycle::Delivery model

**Files:**
- Create: `enterprise/app/models/captain/lifecycle/delivery.rb`
- Create: `spec/enterprise/models/captain/lifecycle/delivery_spec.rb`
- Create: `spec/factories/captain_lifecycle_deliveries.rb`

- [ ] **Step 1: Write failing spec**

```ruby
# spec/enterprise/models/captain/lifecycle/delivery_spec.rb
require 'rails_helper'

RSpec.describe Captain::Lifecycle::Delivery, type: :model do
  describe 'associations' do
    it { is_expected.to belong_to(:account) }
    it { is_expected.to belong_to(:lifecycle_rule).class_name('Captain::Lifecycle::Rule').optional }
    it { is_expected.to belong_to(:captain_reservation).class_name('Captain::Reservation') }
    it { is_expected.to belong_to(:conversation).optional }
    it { is_expected.to belong_to(:message).optional }
    it { is_expected.to belong_to(:inbox).optional }
  end

  describe 'validations' do
    subject { build(:captain_lifecycle_delivery) }
    it { is_expected.to validate_presence_of(:fire_at) }
    it { is_expected.to validate_inclusion_of(:status).in_array(%w[scheduled sent skipped failed cancelled]) }
  end

  describe '.scheduled / .sent / .skipped' do
    it 'scopes by status' do
      s = create(:captain_lifecycle_delivery, status: 'scheduled')
      create(:captain_lifecycle_delivery, status: 'sent')
      expect(described_class.scheduled).to contain_exactly(s)
    end
  end

  describe '.count_sent_for_reservation' do
    let(:reservation) { create(:captain_reservation) }

    it 'counts only sent scheduled_lifecycle deliveries' do
      create(:captain_lifecycle_delivery, captain_reservation: reservation, status: 'sent', origin: 'scheduled_lifecycle')
      create(:captain_lifecycle_delivery, captain_reservation: reservation, status: 'sent', origin: 'scheduled_lifecycle')
      create(:captain_lifecycle_delivery, captain_reservation: reservation, status: 'skipped', origin: 'scheduled_lifecycle')
      create(:captain_lifecycle_delivery, captain_reservation: reservation, status: 'sent', origin: 'concierge_reply')

      expect(described_class.count_sent_for_reservation(reservation.id)).to eq(2)
    end
  end

  describe '#mark_skipped!' do
    let(:delivery) { create(:captain_lifecycle_delivery, status: 'scheduled') }

    it 'updates status and skip_reason' do
      delivery.mark_skipped!('quiet_hours')
      expect(delivery.reload.status).to eq('skipped')
      expect(delivery.skip_reason).to eq('quiet_hours')
    end
  end

  describe '#mark_cancelled!' do
    let(:delivery) { create(:captain_lifecycle_delivery, status: 'scheduled') }

    it 'updates status' do
      delivery.mark_cancelled!
      expect(delivery.reload.status).to eq('cancelled')
    end
  end
end
```

- [ ] **Step 2: Write factory**

```ruby
# spec/factories/captain_lifecycle_deliveries.rb
FactoryBot.define do
  factory :captain_lifecycle_delivery, class: 'Captain::Lifecycle::Delivery' do
    account
    lifecycle_rule { association :captain_lifecycle_rule, account: account }
    captain_reservation { association :captain_reservation, account: account }
    fire_at { 1.hour.from_now }
    status { 'scheduled' }
    origin { 'scheduled_lifecycle' }
  end
end
```

- [ ] **Step 3: Run spec to verify failure**

Run: `bundle exec rspec spec/enterprise/models/captain/lifecycle/delivery_spec.rb`
Expected: FAIL — `uninitialized constant Captain::Lifecycle::Delivery`.

- [ ] **Step 4: Write the model**

```ruby
# enterprise/app/models/captain/lifecycle/delivery.rb
class Captain::Lifecycle::Delivery < ApplicationRecord
  self.table_name = 'captain_lifecycle_deliveries'

  STATUSES = %w[scheduled sent skipped failed cancelled].freeze

  belongs_to :account
  belongs_to :lifecycle_rule, class_name: 'Captain::Lifecycle::Rule', optional: true
  belongs_to :captain_reservation, class_name: 'Captain::Reservation'
  belongs_to :conversation, optional: true
  belongs_to :message, optional: true
  belongs_to :inbox, optional: true

  validates :fire_at, presence: true
  validates :status, inclusion: { in: STATUSES }

  scope :scheduled, -> { where(status: 'scheduled') }
  scope :sent, -> { where(status: 'sent') }
  scope :skipped, -> { where(status: 'skipped') }
  scope :for_reservation, ->(id) { where(captain_reservation_id: id) }

  def self.count_sent_for_reservation(reservation_id)
    for_reservation(reservation_id)
      .where(status: 'sent', origin: 'scheduled_lifecycle')
      .count
  end

  def mark_skipped!(reason)
    update!(status: 'skipped', skip_reason: reason)
  end

  def mark_cancelled!
    update!(status: 'cancelled')
  end

  def mark_sent!(message:, conversation:, rendered_body:)
    update!(
      status: 'sent',
      sent_at: Time.current,
      message_id: message.id,
      conversation_id: conversation.id,
      rendered_body: rendered_body
    )
  end

  def mark_failed!(error)
    update!(status: 'failed', failure_reason: error.to_s.first(2000))
  end
end
```

- [ ] **Step 5: Run spec to verify pass**

Run: `bundle exec rspec spec/enterprise/models/captain/lifecycle/delivery_spec.rb`
Expected: all examples pass.

- [ ] **Step 6: Commit**

```bash
git add enterprise/app/models/captain/lifecycle/delivery.rb spec/enterprise/models/captain/lifecycle/delivery_spec.rb spec/factories/captain_lifecycle_deliveries.rb
git commit -m "feat(lifecycle): add Captain::Lifecycle::Delivery model with helpers"
```

---

## Task 5: Captain::Unit concierge accessors

Adds helper methods pro jsonb `concierge_config` pra não espalhar `config['knowledge']` pelo codebase.

**Files:**
- Modify: `enterprise/app/models/captain/unit.rb`
- Create: `spec/enterprise/models/captain/unit_concierge_spec.rb`

- [ ] **Step 1: Write failing spec**

```ruby
# spec/enterprise/models/captain/unit_concierge_spec.rb
require 'rails_helper'

RSpec.describe Captain::Unit, 'concierge accessors' do
  subject(:unit) { build(:captain_unit, concierge_config: config) }

  context 'when config is empty' do
    let(:config) { {} }

    it '#concierge_persona_name defaults to Sofia' do
      expect(unit.concierge_persona_name).to eq('Sofia')
    end

    it '#concierge_knowledge is empty string' do
      expect(unit.concierge_knowledge).to eq('')
    end

    it '#concierge_variables is empty hash' do
      expect(unit.concierge_variables).to eq({})
    end
  end

  context 'when config is populated' do
    let(:config) do
      {
        'persona_name' => 'Alice',
        'knowledge' => '## Sobre o hotel\n...',
        'variables' => { 'wifi_password' => 'hotel1001' }
      }
    end

    it 'returns persona_name from config' do
      expect(unit.concierge_persona_name).to eq('Alice')
    end

    it 'returns knowledge from config' do
      expect(unit.concierge_knowledge).to eq('## Sobre o hotel\n...')
    end

    it 'returns variables from config' do
      expect(unit.concierge_variables).to eq('wifi_password' => 'hotel1001')
    end
  end

  describe '#concierge_configured?' do
    it 'is false when inbox missing' do
      unit = build(:captain_unit, concierge_inbox_id: nil)
      expect(unit.concierge_configured?).to be(false)
    end

    it 'is true when inbox present' do
      inbox = create(:inbox)
      unit = build(:captain_unit, concierge_inbox_id: inbox.id)
      expect(unit.concierge_configured?).to be(true)
    end
  end
end
```

- [ ] **Step 2: Run spec to verify failure**

Run: `bundle exec rspec spec/enterprise/models/captain/unit_concierge_spec.rb`
Expected: FAIL — `undefined method 'concierge_persona_name'`.

- [ ] **Step 3: Add accessors to Captain::Unit**

Append to `enterprise/app/models/captain/unit.rb` (before the final `end`):

```ruby
  belongs_to :concierge_inbox, class_name: 'Inbox', optional: true

  def concierge_persona_name
    concierge_config_hash['persona_name'].presence || 'Sofia'
  end

  def concierge_knowledge
    concierge_config_hash['knowledge'].to_s
  end

  def concierge_variables
    concierge_config_hash['variables'].to_h
  end

  def concierge_configured?
    concierge_inbox_id.present?
  end

  private

  def concierge_config_hash
    (concierge_config || {}).with_indifferent_access
  end
```

(If `private` already exists in the class, place the helper above it and keep only the new public methods in the public section.)

- [ ] **Step 4: Run spec to verify pass**

Run: `bundle exec rspec spec/enterprise/models/captain/unit_concierge_spec.rb`
Expected: all examples pass.

- [ ] **Step 5: Commit**

```bash
git add enterprise/app/models/captain/unit.rb spec/enterprise/models/captain/unit_concierge_spec.rb
git commit -m "feat(lifecycle): add concierge_* accessors to Captain::Unit"
```

---

## Task 6: Wuzapi::Client interactive message methods

WuzAPI supports buttons/list/url via its REST endpoints. Add 3 new client methods.

**Files:**
- Modify: `app/services/wuzapi/client.rb`
- Create: `spec/services/wuzapi/client_interactive_spec.rb`

- [ ] **Step 1: Write failing spec (use WebMock)**

```ruby
# spec/services/wuzapi/client_interactive_spec.rb
require 'rails_helper'

RSpec.describe Wuzapi::Client, 'interactive messages' do
  let(:base_url) { 'https://wuzapi.test' }
  let(:client) { described_class.new(base_url) }
  let(:user_token) { 'tok' }
  let(:phone) { '5561999999999' }

  describe '#send_buttons' do
    it 'POSTs to /chat/sendbuttons with buttons payload' do
      stub = stub_request(:post, "#{base_url}/chat/sendbuttons")
        .with(
          headers: { 'Token' => user_token },
          body: hash_including(
            Phone: phone,
            Text: 'Curtiu?',
            Buttons: [
              { DisplayText: 'Sim' },
              { DisplayText: 'Não' }
            ]
          )
        )
        .to_return(status: 200, body: { Id: 'msg-1' }.to_json, headers: { 'Content-Type' => 'application/json' })

      response = client.send_buttons(
        user_token, phone, 'Curtiu?',
        [{ text: 'Sim' }, { text: 'Não' }]
      )
      expect(response).to be_success
      expect(stub).to have_been_requested
    end
  end

  describe '#send_list' do
    it 'POSTs to /chat/sendlist with sections' do
      stub = stub_request(:post, "#{base_url}/chat/sendlist")
        .with(headers: { 'Token' => user_token })
        .to_return(status: 200, body: { Id: 'msg-2' }.to_json, headers: { 'Content-Type' => 'application/json' })

      response = client.send_list(
        user_token, phone,
        text: 'Cardápio',
        button_text: 'Ver opções',
        sections: [{ title: 'Bebidas', rows: [{ title: 'Água', row_id: 'agua' }] }]
      )
      expect(response).to be_success
      expect(stub).to have_been_requested
    end
  end

  describe '#send_url_button' do
    it 'POSTs to /chat/sendbuttons with URL button' do
      stub = stub_request(:post, "#{base_url}/chat/sendbuttons")
        .with(body: hash_including(Buttons: [hash_including(Type: 'url')]))
        .to_return(status: 200, body: { Id: 'msg-3' }.to_json, headers: { 'Content-Type' => 'application/json' })

      response = client.send_url_button(user_token, phone,
                                         text: 'Avalie no Google',
                                         button_text: 'Avaliar',
                                         url: 'https://g.page/r/XYZ')
      expect(response).to be_success
      expect(stub).to have_been_requested
    end
  end
end
```

- [ ] **Step 2: Run spec to verify failure**

Run: `bundle exec rspec spec/services/wuzapi/client_interactive_spec.rb`
Expected: FAIL — `undefined method 'send_buttons' for #<Wuzapi::Client>`.

- [ ] **Step 3: Add methods to Wuzapi::Client**

Insert before the `def send_reaction` method (line ~70):

```ruby
  # Sends quick-reply buttons (up to 3 by WhatsApp limit).
  # buttons: array of { text: String }
  def send_buttons(user_token, phone_number, text, buttons)
    payload = {
      Phone: phone_number,
      Text: text,
      Buttons: buttons.map { |b| { DisplayText: b[:text] || b['text'] } }
    }
    request(:post, '/chat/sendbuttons', payload, user_auth_headers(user_token))
  end

  # Sends a list menu (sections with rows, up to 10 rows total).
  # sections: array of { title:, rows: [{ title:, description:, row_id: }] }
  def send_list(user_token, phone_number, text:, button_text:, sections:, footer: nil)
    payload = {
      Phone: phone_number,
      Text: text,
      ButtonText: button_text,
      FooterText: footer,
      Sections: sections.map do |s|
        {
          Title: s[:title] || s['title'],
          Rows: Array(s[:rows] || s['rows']).map do |r|
            { Title: r[:title] || r['title'], Description: r[:description] || r['description'], RowId: r[:row_id] || r['row_id'] }
          end
        }
      end
    }.compact
    request(:post, '/chat/sendlist', payload, user_auth_headers(user_token))
  end

  # Sends a single button that opens a URL when clicked.
  def send_url_button(user_token, phone_number, text:, button_text:, url:)
    payload = {
      Phone: phone_number,
      Text: text,
      Buttons: [{ Type: 'url', DisplayText: button_text, Url: url }]
    }
    request(:post, '/chat/sendbuttons', payload, user_auth_headers(user_token))
  end
```

- [ ] **Step 4: Run spec to verify pass**

Run: `bundle exec rspec spec/services/wuzapi/client_interactive_spec.rb`
Expected: all examples pass.

- [ ] **Step 5: Commit**

```bash
git add app/services/wuzapi/client.rb spec/services/wuzapi/client_interactive_spec.rb
git commit -m "feat(wuzapi): add send_buttons, send_list, send_url_button methods"
```

---

## Task 7: WuzapiService dispatch for interactive messages

Wires the new client methods through the provider so that outgoing messages with structured payload go out as buttons/list instead of plain text.

**Files:**
- Modify: `app/services/whatsapp/providers/wuzapi_service.rb`
- Create: `spec/services/whatsapp/providers/wuzapi_interactive_spec.rb`

- [ ] **Step 1: Write failing spec**

```ruby
# spec/services/whatsapp/providers/wuzapi_interactive_spec.rb
require 'rails_helper'

RSpec.describe Whatsapp::Providers::WuzapiService, 'interactive send' do
  let(:channel) { create(:channel_whatsapp, provider: 'wuzapi') }
  let(:service) { described_class.new(whatsapp_channel: channel) }
  let(:phone) { '+5561999999999' }
  let(:wuzapi_client) { instance_double(Wuzapi::Client) }

  before do
    allow(Wuzapi::Client).to receive(:new).and_return(wuzapi_client)
    allow(channel).to receive(:wuzapi_user_token).and_return('tok')
  end

  describe '#send_interactive_message' do
    it 'dispatches quick_reply buttons' do
      payload = { 'type' => 'quick_reply', 'body' => 'Curtiu?',
                  'buttons' => [{ 'id' => 'yes', 'text' => 'Sim' }] }
      expect(wuzapi_client).to receive(:send_buttons)
        .with('tok', '5561999999999', 'Curtiu?', [{ text: 'Sim' }])
        .and_return(instance_double(Faraday::Response, success?: true, body: '{"Id":"m-1"}'))

      service.send_interactive_message(phone, payload)
    end

    it 'dispatches url_button' do
      payload = { 'type' => 'url_button', 'body' => 'Avalie',
                  'button' => { 'text' => 'Abrir', 'url' => 'https://g.page/r/1' } }
      expect(wuzapi_client).to receive(:send_url_button)
        .with('tok', '5561999999999', text: 'Avalie', button_text: 'Abrir', url: 'https://g.page/r/1')
        .and_return(instance_double(Faraday::Response, success?: true, body: '{"Id":"m-2"}'))

      service.send_interactive_message(phone, payload)
    end

    it 'dispatches list' do
      payload = { 'type' => 'list', 'body' => 'Cardápio', 'button_text' => 'Ver',
                  'sections' => [{ 'title' => 'Bebidas', 'rows' => [{ 'title' => 'Água', 'row_id' => 'a1' }] }] }
      expect(wuzapi_client).to receive(:send_list).and_return(
        instance_double(Faraday::Response, success?: true, body: '{"Id":"m-3"}')
      )
      service.send_interactive_message(phone, payload)
    end

    it 'raises for unknown type' do
      expect { service.send_interactive_message(phone, 'type' => 'xyz') }
        .to raise_error(ArgumentError, /unsupported interactive type/)
    end
  end
end
```

- [ ] **Step 2: Run spec to verify failure**

Run: `bundle exec rspec spec/services/whatsapp/providers/wuzapi_interactive_spec.rb`
Expected: FAIL — `undefined method 'send_interactive_message'`.

- [ ] **Step 3: Add method to WuzapiService**

Insert after `def send_template` (around line 55):

```ruby
  # Dispatches an interactive message (buttons / list / url_button).
  # Called by the lifecycle dispatcher when a rule has message_type != 'text'.
  # payload: already-rendered hash from Captain::Lifecycle::Rule#message_payload
  def send_interactive_message(phone_number, payload)
    normalized_phone = normalize_phone(phone_number)
    user_token = @whatsapp_channel.wuzapi_user_token

    case payload['type'].to_s
    when 'quick_reply', 'buttons'
      buttons = Array(payload['buttons']).map { |b| { text: b['text'] || b[:text] } }
      client.send_buttons(user_token, normalized_phone, payload['body'].to_s, buttons)
    when 'url_button'
      button = payload['button'] || {}
      client.send_url_button(
        user_token, normalized_phone,
        text: payload['body'].to_s,
        button_text: button['text'].to_s,
        url: button['url'].to_s
      )
    when 'list'
      client.send_list(
        user_token, normalized_phone,
        text: payload['body'].to_s,
        button_text: payload['button_text'].to_s,
        sections: payload['sections'] || []
      )
    else
      raise ArgumentError, "unsupported interactive type: #{payload['type'].inspect}"
    end
  end
```

- [ ] **Step 4: Run spec to verify pass**

Run: `bundle exec rspec spec/services/whatsapp/providers/wuzapi_interactive_spec.rb`
Expected: all examples pass.

- [ ] **Step 5: Commit**

```bash
git add app/services/whatsapp/providers/wuzapi_service.rb spec/services/whatsapp/providers/wuzapi_interactive_spec.rb
git commit -m "feat(wuzapi): dispatch interactive messages (buttons/list/url_button)"
```

---

## Task 8: Captain::Lifecycle::EventResolver

Pure function: given a reservation and an event name, return the timestamp that represents "when that event happens" (or raise if not applicable).

**Files:**
- Create: `enterprise/app/services/captain/lifecycle/event_resolver.rb`
- Create: `spec/enterprise/services/captain/lifecycle/event_resolver_spec.rb`

- [ ] **Step 1: Write failing spec**

```ruby
# spec/enterprise/services/captain/lifecycle/event_resolver_spec.rb
require 'rails_helper'

RSpec.describe Captain::Lifecycle::EventResolver do
  let(:reservation) do
    build(:captain_reservation,
          check_in_at: Time.zone.parse('2026-04-20 22:00:00'),
          check_out_at: Time.zone.parse('2026-04-21 12:00:00'),
          updated_at: Time.zone.parse('2026-04-19 10:00:00'))
  end

  describe '.resolve' do
    it 'returns check_in_at for checkin.scheduled_at' do
      expect(described_class.resolve(reservation, 'checkin.scheduled_at'))
        .to eq(reservation.check_in_at)
    end

    it 'returns check_out_at for checkout.scheduled_at' do
      expect(described_class.resolve(reservation, 'checkout.scheduled_at'))
        .to eq(reservation.check_out_at)
    end

    it 'returns updated_at for reservation.confirmed' do
      expect(described_class.resolve(reservation, 'reservation.confirmed'))
        .to eq(reservation.updated_at)
    end

    it 'returns nil for checkin.detected (not yet supported)' do
      expect(described_class.resolve(reservation, 'checkin.detected')).to be_nil
    end

    it 'raises for unknown event' do
      expect { described_class.resolve(reservation, 'unknown.event') }
        .to raise_error(ArgumentError, /unknown event/)
    end
  end
end
```

- [ ] **Step 2: Run spec to verify failure**

Run: `bundle exec rspec spec/enterprise/services/captain/lifecycle/event_resolver_spec.rb`
Expected: FAIL — `uninitialized constant Captain::Lifecycle::EventResolver`.

- [ ] **Step 3: Implement the resolver**

```ruby
# enterprise/app/services/captain/lifecycle/event_resolver.rb
class Captain::Lifecycle::EventResolver
  UNSUPPORTED_IN_MVP = %w[checkin.detected checkout.detected].freeze

  def self.resolve(reservation, event_name)
    return nil if UNSUPPORTED_IN_MVP.include?(event_name)

    case event_name
    when 'reservation.confirmed'
      reservation.updated_at
    when 'checkin.scheduled_at'
      reservation.check_in_at
    when 'checkout.scheduled_at'
      reservation.check_out_at
    when 'reservation.cancelled'
      reservation.updated_at if reservation.status.to_s == 'cancelled'
    when 'reservation.no_show'
      reservation.check_in_at&.+ 1.hour
    else
      raise ArgumentError, "unknown event: #{event_name.inspect}"
    end
  end
end
```

- [ ] **Step 4: Run spec to verify pass**

Run: `bundle exec rspec spec/enterprise/services/captain/lifecycle/event_resolver_spec.rb`
Expected: all examples pass.

- [ ] **Step 5: Commit**

```bash
git add enterprise/app/services/captain/lifecycle/event_resolver.rb spec/enterprise/services/captain/lifecycle/event_resolver_spec.rb
git commit -m "feat(lifecycle): add EventResolver service"
```

---

## Task 9: Captain::Lifecycle::Scheduler service

Orchestrates scheduling deliveries when a reservation is created/updated.

**Files:**
- Create: `enterprise/app/services/captain/lifecycle/scheduler.rb`
- Create: `spec/enterprise/services/captain/lifecycle/scheduler_spec.rb`

- [ ] **Step 1: Write failing spec**

```ruby
# spec/enterprise/services/captain/lifecycle/scheduler_spec.rb
require 'rails_helper'

RSpec.describe Captain::Lifecycle::Scheduler do
  let(:account) { create(:account) }
  let(:unit) { create(:captain_unit, account: account) }
  let(:reservation) do
    create(:captain_reservation,
           account: account,
           captain_unit: unit,
           check_in_at: 2.hours.from_now,
           check_out_at: 10.hours.from_now)
  end

  describe '.schedule_for' do
    let!(:matching_rule) do
      create(:captain_lifecycle_rule,
             account: account,
             event: 'checkin.scheduled_at',
             offset_minutes: -10)
    end

    it 'creates a scheduled delivery for each matching enabled rule' do
      expect { described_class.schedule_for(reservation) }
        .to change { Captain::Lifecycle::Delivery.count }.by(1)
    end

    it 'sets fire_at to event_time + offset' do
      described_class.schedule_for(reservation)
      delivery = Captain::Lifecycle::Delivery.last
      expect(delivery.fire_at).to be_within(1.second).of(reservation.check_in_at - 10.minutes)
    end

    it 'enqueues a Sidekiq job for fire_at' do
      expect(Captain::Lifecycle::DispatcherJob).to receive(:perform_at)
        .with(kind_of(Time), kind_of(Integer))
      described_class.schedule_for(reservation)
    end

    it 'skips rules whose fire_at is in the past' do
      create(:captain_lifecycle_rule,
             account: account,
             event: 'checkin.scheduled_at',
             offset_minutes: -3.days.to_i / 60)
      # offset of -3 days means fire_at ~= 3 days ago
      matching_rule.destroy!
      expect { described_class.schedule_for(reservation) }
        .not_to change { Captain::Lifecycle::Delivery.count }
    end

    it 'skips disabled rules' do
      matching_rule.update!(enabled: false)
      expect { described_class.schedule_for(reservation) }
        .not_to change { Captain::Lifecycle::Delivery.count }
    end

    it 'skips rules where filter does not match' do
      matching_rule.update!(filters: { 'categorias' => ['DoesNotExist'] })
      expect { described_class.schedule_for(reservation) }
        .not_to change { Captain::Lifecycle::Delivery.count }
    end
  end

  describe '.cancel_pending' do
    let!(:delivery) do
      create(:captain_lifecycle_delivery,
             account: account,
             captain_reservation: reservation,
             status: 'scheduled')
    end
    let!(:sent) do
      create(:captain_lifecycle_delivery,
             account: account,
             captain_reservation: reservation,
             status: 'sent')
    end

    it 'marks scheduled deliveries as cancelled' do
      described_class.cancel_pending(reservation)
      expect(delivery.reload.status).to eq('cancelled')
    end

    it 'does not touch sent deliveries' do
      described_class.cancel_pending(reservation)
      expect(sent.reload.status).to eq('sent')
    end
  end

  describe '.reschedule_for_checkin_change' do
    let!(:checkin_rule) do
      create(:captain_lifecycle_rule,
             account: account,
             event: 'checkin.scheduled_at',
             offset_minutes: -10)
    end
    let!(:other_rule) do
      create(:captain_lifecycle_rule,
             account: account,
             event: 'reservation.confirmed',
             offset_minutes: 0)
    end

    before do
      described_class.schedule_for(reservation)
    end

    it 'cancels checkin-based scheduled deliveries and reschedules' do
      reservation.update!(check_in_at: reservation.check_in_at + 1.hour)
      expect { described_class.reschedule_for_checkin_change(reservation) }
        .to change { Captain::Lifecycle::Delivery.where(status: 'cancelled').count }.by(1)
    end

    it 'does not touch non-checkin deliveries' do
      original = Captain::Lifecycle::Delivery
                 .where(lifecycle_rule_id: other_rule.id)
                 .pluck(:status)
      described_class.reschedule_for_checkin_change(reservation)
      still_same = Captain::Lifecycle::Delivery
                   .where(lifecycle_rule_id: other_rule.id)
                   .pluck(:status)
      expect(still_same).to eq(original)
    end
  end
end
```

- [ ] **Step 2: Run spec to verify failure**

Run: `bundle exec rspec spec/enterprise/services/captain/lifecycle/scheduler_spec.rb`
Expected: FAIL — `uninitialized constant Captain::Lifecycle::Scheduler`.

- [ ] **Step 3: Implement scheduler**

```ruby
# enterprise/app/services/captain/lifecycle/scheduler.rb
class Captain::Lifecycle::Scheduler
  CHECKIN_EVENTS = %w[checkin.scheduled_at checkin.detected].freeze
  CHECKOUT_EVENTS = %w[checkout.scheduled_at checkout.detected].freeze

  class << self
    def schedule_for(reservation)
      rules = Captain::Lifecycle::Rule
              .where(account_id: reservation.account_id)
              .active
              .to_a

      rules.each do |rule|
        next unless rule.matches_reservation?(reservation)

        fire_at = compute_fire_at(reservation, rule)
        next if fire_at.nil? || fire_at <= Time.current

        delivery = Captain::Lifecycle::Delivery.create!(
          account_id: reservation.account_id,
          lifecycle_rule_id: rule.id,
          captain_reservation_id: reservation.id,
          inbox_id: reservation.unit&.concierge_inbox_id,
          fire_at: fire_at,
          status: 'scheduled',
          origin: 'scheduled_lifecycle'
        )

        Captain::Lifecycle::DispatcherJob.perform_at(fire_at, delivery.id)
      end
    end

    def cancel_pending(reservation)
      Captain::Lifecycle::Delivery
        .where(captain_reservation_id: reservation.id, status: 'scheduled')
        .update_all(status: 'cancelled', updated_at: Time.current)
    end

    def reschedule_for_checkin_change(reservation)
      pending = Captain::Lifecycle::Delivery
                .where(captain_reservation_id: reservation.id, status: 'scheduled')
                .joins('INNER JOIN captain_lifecycle_rules ON captain_lifecycle_rules.id = captain_lifecycle_deliveries.lifecycle_rule_id')
                .where('captain_lifecycle_rules.event IN (?)', CHECKIN_EVENTS)
      pending.update_all(status: 'cancelled', updated_at: Time.current)

      checkin_rules = Captain::Lifecycle::Rule
                      .where(account_id: reservation.account_id, event: CHECKIN_EVENTS)
                      .active
      checkin_rules.each { |r| schedule_one_rule(reservation, r) }
    end

    private

    def compute_fire_at(reservation, rule)
      event_time = Captain::Lifecycle::EventResolver.resolve(reservation, rule.event)
      return nil if event_time.nil?

      event_time + rule.offset_minutes.minutes
    end

    def schedule_one_rule(reservation, rule)
      return unless rule.matches_reservation?(reservation)

      fire_at = compute_fire_at(reservation, rule)
      return if fire_at.nil? || fire_at <= Time.current

      delivery = Captain::Lifecycle::Delivery.create!(
        account_id: reservation.account_id,
        lifecycle_rule_id: rule.id,
        captain_reservation_id: reservation.id,
        inbox_id: reservation.unit&.concierge_inbox_id,
        fire_at: fire_at,
        status: 'scheduled',
        origin: 'scheduled_lifecycle'
      )
      Captain::Lifecycle::DispatcherJob.perform_at(fire_at, delivery.id)
    end
  end
end
```

Note: this references `Captain::Lifecycle::DispatcherJob`. The full implementation (Dispatcher-calling body) is Task 16 — here we only need a stub so that `expect(...).to receive(:perform_at)` in the scheduler spec resolves the constant. Create the stub now:

```ruby
# enterprise/app/jobs/captain/lifecycle/dispatcher_job.rb
class Captain::Lifecycle::DispatcherJob < ApplicationJob
  queue_as :default

  def perform(delivery_id)
    # Stub — full implementation lands in Task 16.
  end
end
```

- [ ] **Step 4: Run spec to verify pass**

Run: `bundle exec rspec spec/enterprise/services/captain/lifecycle/scheduler_spec.rb`
Expected: all examples pass.

- [ ] **Step 5: Commit**

```bash
git add enterprise/app/services/captain/lifecycle/scheduler.rb enterprise/app/jobs/captain/lifecycle/dispatcher_job.rb spec/enterprise/services/captain/lifecycle/scheduler_spec.rb
git commit -m "feat(lifecycle): add Scheduler service and DispatcherJob stub"
```

---

## Task 10: Captain::Reservation lifecycle hooks

Wires `Captain::Reservation` to the Scheduler via `after_commit` callbacks.

**Files:**
- Modify: `enterprise/app/models/captain/reservation.rb`
- Create: `spec/enterprise/models/captain/reservation_lifecycle_hooks_spec.rb`

- [ ] **Step 1: Write failing spec**

```ruby
# spec/enterprise/models/captain/reservation_lifecycle_hooks_spec.rb
require 'rails_helper'

RSpec.describe Captain::Reservation, 'lifecycle hooks' do
  let(:account) { create(:account) }
  let(:unit) { create(:captain_unit, account: account) }

  describe 'after create' do
    it 'calls Scheduler.schedule_for' do
      expect(Captain::Lifecycle::Scheduler).to receive(:schedule_for).with(kind_of(Captain::Reservation))
      create(:captain_reservation, account: account, captain_unit: unit,
                                   check_in_at: 2.hours.from_now, check_out_at: 10.hours.from_now)
    end
  end

  describe 'after update (status → cancelled)' do
    let(:reservation) do
      create(:captain_reservation, account: account, captain_unit: unit,
                                    check_in_at: 2.hours.from_now, check_out_at: 10.hours.from_now)
    end

    it 'cancels pending deliveries' do
      expect(Captain::Lifecycle::Scheduler).to receive(:cancel_pending).with(reservation)
      reservation.update!(status: 'cancelled')
    end
  end

  describe 'after update (check_in_at changed)' do
    let(:reservation) do
      create(:captain_reservation, account: account, captain_unit: unit,
                                    check_in_at: 2.hours.from_now, check_out_at: 10.hours.from_now)
    end

    it 'reschedules checkin-based deliveries' do
      expect(Captain::Lifecycle::Scheduler).to receive(:reschedule_for_checkin_change).with(reservation)
      reservation.update!(check_in_at: 3.hours.from_now)
    end
  end
end
```

- [ ] **Step 2: Run spec to verify failure**

Run: `bundle exec rspec spec/enterprise/models/captain/reservation_lifecycle_hooks_spec.rb`
Expected: FAIL — hooks do not exist yet.

- [ ] **Step 3: Add hooks to Captain::Reservation**

In `enterprise/app/models/captain/reservation.rb`, add alongside existing callbacks:

```ruby
  after_create_commit :schedule_lifecycle_rules
  after_update_commit :handle_lifecycle_status_change, if: :saved_change_to_status?
  after_update_commit :handle_lifecycle_checkin_change, if: :saved_change_to_check_in_at?

  private

  def schedule_lifecycle_rules
    Captain::Lifecycle::Scheduler.schedule_for(self)
  rescue StandardError => e
    Rails.logger.error("[Lifecycle] schedule_for failed for reservation #{id}: #{e.class} #{e.message}")
  end

  def handle_lifecycle_status_change
    return unless %w[cancelled no_show].include?(status.to_s)

    Captain::Lifecycle::Scheduler.cancel_pending(self)
  rescue StandardError => e
    Rails.logger.error("[Lifecycle] cancel_pending failed for reservation #{id}: #{e.class} #{e.message}")
  end

  def handle_lifecycle_checkin_change
    Captain::Lifecycle::Scheduler.reschedule_for_checkin_change(self)
  rescue StandardError => e
    Rails.logger.error("[Lifecycle] reschedule failed for reservation #{id}: #{e.class} #{e.message}")
  end
```

If `private` already exists further down, put these methods below the existing private section or use a separate `private` block.

- [ ] **Step 4: Run spec to verify pass**

Run: `bundle exec rspec spec/enterprise/models/captain/reservation_lifecycle_hooks_spec.rb`
Expected: all examples pass.

- [ ] **Step 5: Run full reservation spec to check for regressions**

Run: `bundle exec rspec spec/enterprise/models/captain/reservation_spec.rb`
Expected: all examples still pass (no regressions in existing hooks).

- [ ] **Step 6: Commit**

```bash
git add enterprise/app/models/captain/reservation.rb spec/enterprise/models/captain/reservation_lifecycle_hooks_spec.rb
git commit -m "feat(lifecycle): wire Captain::Reservation lifecycle hooks"
```

---

## Task 11: Captain::Lifecycle::ContextBuilder

Builds the variable hash that gets fed into the Liquid template during render.

**Files:**
- Create: `enterprise/app/services/captain/lifecycle/context_builder.rb`
- Create: `spec/enterprise/services/captain/lifecycle/context_builder_spec.rb`

- [ ] **Step 1: Write failing spec**

```ruby
# spec/enterprise/services/captain/lifecycle/context_builder_spec.rb
require 'rails_helper'

RSpec.describe Captain::Lifecycle::ContextBuilder do
  let(:account) { create(:account) }
  let(:unit) do
    create(:captain_unit,
           account: account,
           name: 'Águas Lindas',
           concierge_config: {
             'persona_name' => 'Sofia',
             'variables' => { 'wifi_password' => 'hotel1001', 'menu_link' => 'https://menu.x' }
           })
  end
  let(:contact) { create(:contact, account: account, name: 'João Silva', phone_number: '+5561999999999') }
  let(:reservation) do
    create(:captain_reservation,
           account: account,
           captain_unit: unit,
           contact: contact,
           suite_identifier: 'Alexa',
           total_amount: 160.0,
           check_in_at: Time.zone.parse('2026-04-20 22:00:00'),
           check_out_at: Time.zone.parse('2026-04-21 12:00:00'),
           metadata: { 'permanencia' => 'Pernoite' })
  end

  describe '.build' do
    subject(:ctx) { described_class.build(reservation) }

    it 'includes customer.name and first_name' do
      expect(ctx['customer']['name']).to eq('João Silva')
      expect(ctx['customer']['first_name']).to eq('João')
    end

    it 'includes customer.phone' do
      expect(ctx['customer']['phone']).to eq('+5561999999999')
    end

    it 'includes reservation.suite' do
      expect(ctx['reservation']['suite']).to eq('Alexa')
    end

    it 'includes reservation.unit_name' do
      expect(ctx['reservation']['unit_name']).to eq('Águas Lindas')
    end

    it 'formats reservation.amount as BRL' do
      expect(ctx['reservation']['amount']).to include('R$')
      expect(ctx['reservation']['amount']).to include('160')
    end

    it 'includes reservation.permanencia' do
      expect(ctx['reservation']['permanencia']).to eq('Pernoite')
    end

    it 'includes hotel.wifi_password from unit variables' do
      expect(ctx['hotel']['wifi_password']).to eq('hotel1001')
    end

    it 'includes hotel.menu_link from unit variables' do
      expect(ctx['hotel']['menu_link']).to eq('https://menu.x')
    end
  end
end
```

- [ ] **Step 2: Run spec to verify failure**

Run: `bundle exec rspec spec/enterprise/services/captain/lifecycle/context_builder_spec.rb`
Expected: FAIL — `uninitialized constant Captain::Lifecycle::ContextBuilder`.

- [ ] **Step 3: Implement ContextBuilder**

```ruby
# enterprise/app/services/captain/lifecycle/context_builder.rb
class Captain::Lifecycle::ContextBuilder
  def self.build(reservation)
    new(reservation).build
  end

  def initialize(reservation)
    @reservation = reservation
    @contact = reservation.contact
    @unit = reservation.unit
  end

  def build
    {
      'customer' => customer_context,
      'reservation' => reservation_context,
      'hotel' => hotel_context
    }
  end

  private

  def customer_context
    name = @contact&.name.to_s
    {
      'name' => name,
      'first_name' => name.split.first.to_s,
      'phone' => @contact&.phone_number.to_s,
      'cpf' => @contact&.custom_attributes.to_h['cpf'].to_s
    }
  end

  def reservation_context
    {
      'suite' => @reservation.suite_identifier.to_s,
      'unit_name' => @unit&.name.to_s,
      'check_in_at' => format_datetime(@reservation.check_in_at),
      'check_out_at' => format_datetime(@reservation.check_out_at),
      'amount' => format_money(@reservation.total_amount),
      'permanencia' => @reservation.metadata.to_h['permanencia'].to_s
    }
  end

  def hotel_context
    (@unit&.concierge_variables || {}).stringify_keys
  end

  def format_datetime(value)
    return '' unless value

    I18n.l(value.in_time_zone('America/Sao_Paulo'), format: :short)
  end

  def format_money(value)
    ActiveSupport::NumberHelper.number_to_currency(
      value.to_f,
      unit: 'R$ ',
      separator: ',',
      delimiter: '.'
    )
  end
end
```

- [ ] **Step 4: Run spec to verify pass**

Run: `bundle exec rspec spec/enterprise/services/captain/lifecycle/context_builder_spec.rb`
Expected: all examples pass.

- [ ] **Step 5: Commit**

```bash
git add enterprise/app/services/captain/lifecycle/context_builder.rb spec/enterprise/services/captain/lifecycle/context_builder_spec.rb
git commit -m "feat(lifecycle): add ContextBuilder for Liquid render variables"
```

---

## Task 12: Guards — simple ones (reservation_active, opt_out_label, max_per_reservation)

Three guards that don't need reschedule logic: they either pass or skip. Bundled because all 3 share the same `Guards::Base` interface.

**Files:**
- Create: `enterprise/app/services/captain/lifecycle/guards/base.rb`
- Create: `enterprise/app/services/captain/lifecycle/guards/reservation_active.rb`
- Create: `enterprise/app/services/captain/lifecycle/guards/opt_out_label.rb`
- Create: `enterprise/app/services/captain/lifecycle/guards/max_per_reservation.rb`
- Create: `spec/enterprise/services/captain/lifecycle/guards/reservation_active_spec.rb`
- Create: `spec/enterprise/services/captain/lifecycle/guards/opt_out_label_spec.rb`
- Create: `spec/enterprise/services/captain/lifecycle/guards/max_per_reservation_spec.rb`

- [ ] **Step 1: Write failing spec for reservation_active guard**

```ruby
# spec/enterprise/services/captain/lifecycle/guards/reservation_active_spec.rb
require 'rails_helper'

RSpec.describe Captain::Lifecycle::Guards::ReservationActive do
  let(:reservation) { create(:captain_reservation, status: 'scheduled') }
  let(:delivery) { create(:captain_lifecycle_delivery, captain_reservation: reservation) }

  subject(:guard) { described_class.new(delivery) }

  it 'returns pass for active reservation' do
    expect(guard.check).to eq(action: :pass)
  end

  it 'returns skip for cancelled reservation' do
    reservation.update!(status: 'cancelled')
    expect(guard.check).to eq(action: :skip, reason: 'reservation_cancelled')
  end

  it 'returns skip for no_show reservation' do
    reservation.update!(status: 'no_show') if Captain::Reservation.statuses.key?('no_show')
    result = guard.check
    expect(result[:action]).to eq(:skip) if Captain::Reservation.statuses.key?('no_show')
  end
end
```

- [ ] **Step 2: Run spec to verify failure**

Run: `bundle exec rspec spec/enterprise/services/captain/lifecycle/guards/reservation_active_spec.rb`
Expected: FAIL — `uninitialized constant Captain::Lifecycle::Guards`.

- [ ] **Step 3: Create Guards::Base and ReservationActive**

```ruby
# enterprise/app/services/captain/lifecycle/guards/base.rb
class Captain::Lifecycle::Guards::Base
  def initialize(delivery)
    @delivery = delivery
    @reservation = delivery.captain_reservation
    @account = delivery.account
  end

  def check
    raise NotImplementedError
  end

  protected

  def pass
    { action: :pass }
  end

  def skip(reason)
    { action: :skip, reason: reason }
  end

  def reschedule(new_fire_at)
    { action: :reschedule, fire_at: new_fire_at }
  end
end
```

Also create the namespace module file so Rails autoloading works:

```ruby
# enterprise/app/services/captain/lifecycle/guards.rb
module Captain
  module Lifecycle
    module Guards
    end
  end
end
```

```ruby
# enterprise/app/services/captain/lifecycle/guards/reservation_active.rb
class Captain::Lifecycle::Guards::ReservationActive < Captain::Lifecycle::Guards::Base
  BLOCKING_STATUSES = %w[cancelled no_show].freeze

  def check
    return skip('reservation_cancelled') if BLOCKING_STATUSES.include?(@reservation.status.to_s)

    pass
  end
end
```

- [ ] **Step 4: Run first guard spec to verify pass**

Run: `bundle exec rspec spec/enterprise/services/captain/lifecycle/guards/reservation_active_spec.rb`
Expected: pass.

- [ ] **Step 5: Write failing spec for opt_out_label guard**

```ruby
# spec/enterprise/services/captain/lifecycle/guards/opt_out_label_spec.rb
require 'rails_helper'

RSpec.describe Captain::Lifecycle::Guards::OptOutLabel do
  let(:account) { create(:account) }
  let(:label) { create(:label, account: account, title: 'nao_mandar_auto') }
  let(:config) { create(:captain_lifecycle_config, account: account, opt_out_label: label) }
  let(:contact) { create(:contact, account: account) }
  let(:reservation) { create(:captain_reservation, account: account, contact: contact) }
  let(:delivery) { create(:captain_lifecycle_delivery, account: account, captain_reservation: reservation) }

  subject(:guard) { described_class.new(delivery) }

  before { config } # ensure created

  it 'passes when contact has no opt_out label' do
    expect(guard.check).to eq(action: :pass)
  end

  it 'skips when contact has the configured opt_out label' do
    contact.update!(label_list: [label.title])
    expect(guard.check).to eq(action: :skip, reason: 'opt_out_label')
  end

  it 'passes when account has no opt_out_label configured' do
    config.update!(opt_out_label: nil)
    contact.update!(label_list: [label.title])
    expect(guard.check).to eq(action: :pass)
  end
end
```

- [ ] **Step 6: Implement OptOutLabel guard**

```ruby
# enterprise/app/services/captain/lifecycle/guards/opt_out_label.rb
class Captain::Lifecycle::Guards::OptOutLabel < Captain::Lifecycle::Guards::Base
  def check
    config = Captain::Lifecycle::Config.for_account(@account)
    label = config.opt_out_label
    return pass if label.blank?

    contact = @reservation.contact
    return pass if contact.blank?

    return skip('opt_out_label') if contact.label_list.include?(label.title)

    pass
  end
end
```

- [ ] **Step 7: Run opt_out spec to verify pass**

Run: `bundle exec rspec spec/enterprise/services/captain/lifecycle/guards/opt_out_label_spec.rb`
Expected: pass.

- [ ] **Step 8: Write failing spec for max_per_reservation**

```ruby
# spec/enterprise/services/captain/lifecycle/guards/max_per_reservation_spec.rb
require 'rails_helper'

RSpec.describe Captain::Lifecycle::Guards::MaxPerReservation do
  let(:reservation) { create(:captain_reservation) }
  let(:delivery) { create(:captain_lifecycle_delivery, captain_reservation: reservation) }

  subject(:guard) { described_class.new(delivery) }

  context 'under cap' do
    it 'passes with 0 sent deliveries' do
      expect(guard.check).to eq(action: :pass)
    end

    it 'passes with 4 sent deliveries' do
      4.times do
        create(:captain_lifecycle_delivery,
               captain_reservation: reservation, status: 'sent', origin: 'scheduled_lifecycle')
      end
      expect(guard.check).to eq(action: :pass)
    end
  end

  context 'at or over cap' do
    before do
      5.times do
        create(:captain_lifecycle_delivery,
               captain_reservation: reservation, status: 'sent', origin: 'scheduled_lifecycle')
      end
    end

    it 'skips with max_reached' do
      expect(guard.check).to eq(action: :skip, reason: 'max_reached')
    end
  end

  context 'with concierge replies (non-lifecycle origin)' do
    it 'ignores concierge_reply origin toward the cap' do
      10.times do
        create(:captain_lifecycle_delivery,
               captain_reservation: reservation, status: 'sent', origin: 'concierge_reply')
      end
      expect(guard.check).to eq(action: :pass)
    end
  end
end
```

- [ ] **Step 9: Implement MaxPerReservation guard**

```ruby
# enterprise/app/services/captain/lifecycle/guards/max_per_reservation.rb
class Captain::Lifecycle::Guards::MaxPerReservation < Captain::Lifecycle::Guards::Base
  CAP = 5

  def check
    count = Captain::Lifecycle::Delivery.count_sent_for_reservation(@reservation.id)
    return skip('max_reached') if count >= CAP

    pass
  end
end
```

- [ ] **Step 10: Run max_per_reservation spec to verify pass**

Run: `bundle exec rspec spec/enterprise/services/captain/lifecycle/guards/max_per_reservation_spec.rb`
Expected: pass.

- [ ] **Step 11: Commit**

```bash
git add enterprise/app/services/captain/lifecycle/guards/ spec/enterprise/services/captain/lifecycle/guards/
git commit -m "feat(lifecycle): add base, reservation_active, opt_out_label, max_per_reservation guards"
```

---

## Task 13: Quiet hours guard (Opção C)

Reschedules to the end of the quiet window, but skips with `too_stale` if the delay exceeds 2 hours.

**Files:**
- Create: `enterprise/app/services/captain/lifecycle/guards/quiet_hours.rb`
- Create: `spec/enterprise/services/captain/lifecycle/guards/quiet_hours_spec.rb`

- [ ] **Step 1: Write failing spec**

```ruby
# spec/enterprise/services/captain/lifecycle/guards/quiet_hours_spec.rb
require 'rails_helper'

RSpec.describe Captain::Lifecycle::Guards::QuietHours do
  let(:account) { create(:account) }
  let(:reservation) { create(:captain_reservation, account: account) }
  let(:delivery) do
    create(:captain_lifecycle_delivery,
           account: account, captain_reservation: reservation, fire_at: fire_at)
  end
  subject(:guard) { described_class.new(delivery) }

  context 'when quiet hours disabled' do
    let(:fire_at) { Time.zone.parse('2026-04-15 03:00:00') }
    before { create(:captain_lifecycle_config, account: account, quiet_hours_enabled: false) }

    it 'passes regardless of fire_at' do
      expect(guard.check).to eq(action: :pass)
    end
  end

  context 'when quiet hours enabled (23:00-08:00)' do
    before do
      create(:captain_lifecycle_config,
             account: account,
             quiet_hours_enabled: true,
             quiet_hours_from: '23:00',
             quiet_hours_to: '08:00')
    end

    context 'fire_at outside window (14:00)' do
      let(:fire_at) { Time.zone.parse('2026-04-15 14:00:00') }
      it('passes') { expect(guard.check).to eq(action: :pass) }
    end

    context 'fire_at inside window but close to end (07:45, delay 15min)' do
      let(:fire_at) { Time.zone.parse('2026-04-15 07:45:00') }
      it 'reschedules to 08:00' do
        result = guard.check
        expect(result[:action]).to eq(:reschedule)
        expect(result[:fire_at]).to eq(Time.zone.parse('2026-04-15 08:00:00'))
      end
    end

    context 'fire_at deep inside window (03:00, delay 5h)' do
      let(:fire_at) { Time.zone.parse('2026-04-15 03:00:00') }
      it 'skips with too_stale' do
        expect(guard.check).to eq(action: :skip, reason: 'too_stale')
      end
    end

    context 'fire_at at 23:30 (delay until next 08:00 = 8.5h)' do
      let(:fire_at) { Time.zone.parse('2026-04-15 23:30:00') }
      it 'skips with too_stale' do
        expect(guard.check).to eq(action: :skip, reason: 'too_stale')
      end
    end
  end
end
```

- [ ] **Step 2: Run spec to verify failure**

Run: `bundle exec rspec spec/enterprise/services/captain/lifecycle/guards/quiet_hours_spec.rb`
Expected: FAIL — `uninitialized constant Captain::Lifecycle::Guards::QuietHours`.

- [ ] **Step 3: Implement QuietHours guard**

```ruby
# enterprise/app/services/captain/lifecycle/guards/quiet_hours.rb
class Captain::Lifecycle::Guards::QuietHours < Captain::Lifecycle::Guards::Base
  MAX_DELAY = 2.hours

  def check
    config = Captain::Lifecycle::Config.for_account(@account)
    return pass unless config.quiet_hours_enabled

    fire_at = @delivery.fire_at
    return pass unless in_quiet_window?(fire_at, config)

    delayed_to = next_valid_time(fire_at, config)
    delay = delayed_to - fire_at
    return skip('too_stale') if delay > MAX_DELAY

    reschedule(delayed_to)
  end

  private

  def in_quiet_window?(time, config)
    from = time_of_day(config.quiet_hours_from)
    to = time_of_day(config.quiet_hours_to)
    minute = time.hour * 60 + time.min

    if from < to
      (from...to).cover?(minute)
    else
      minute >= from || minute < to
    end
  end

  def next_valid_time(fire_at, config)
    to_minute = time_of_day(config.quiet_hours_to)
    fire_minute = fire_at.hour * 60 + fire_at.min
    target = fire_at.beginning_of_day + to_minute.minutes
    target += 1.day if fire_minute >= time_of_day(config.quiet_hours_from) && fire_minute >= to_minute
    target
  end

  def time_of_day(t)
    t.hour * 60 + t.min
  end
end
```

- [ ] **Step 4: Run spec to verify pass**

Run: `bundle exec rspec spec/enterprise/services/captain/lifecycle/guards/quiet_hours_spec.rb`
Expected: all examples pass.

- [ ] **Step 5: Commit**

```bash
git add enterprise/app/services/captain/lifecycle/guards/quiet_hours.rb spec/enterprise/services/captain/lifecycle/guards/quiet_hours_spec.rb
git commit -m "feat(lifecycle): add QuietHours guard with 2h staleness limit"
```

---

## Task 14: MinInterval and CustomerReplied guards

Both guards reschedule instead of skip (except when too stale — same rule as QuietHours: 2h max).

**Files:**
- Create: `enterprise/app/services/captain/lifecycle/guards/min_interval.rb`
- Create: `enterprise/app/services/captain/lifecycle/guards/customer_replied.rb`
- Create: `spec/enterprise/services/captain/lifecycle/guards/min_interval_spec.rb`
- Create: `spec/enterprise/services/captain/lifecycle/guards/customer_replied_spec.rb`

- [ ] **Step 1: Write failing spec for min_interval**

```ruby
# spec/enterprise/services/captain/lifecycle/guards/min_interval_spec.rb
require 'rails_helper'

RSpec.describe Captain::Lifecycle::Guards::MinInterval do
  let(:account) { create(:account) }
  let(:reservation) { create(:captain_reservation, account: account) }
  subject(:guard) { described_class.new(delivery) }

  let(:delivery) do
    create(:captain_lifecycle_delivery,
           account: account, captain_reservation: reservation, fire_at: Time.current + 1.minute)
  end

  context 'when min_interval_minutes = 0' do
    before { create(:captain_lifecycle_config, account: account, min_interval_minutes: 0) }

    it 'passes' do
      expect(guard.check).to eq(action: :pass)
    end
  end

  context 'when min_interval_minutes = 30' do
    before { create(:captain_lifecycle_config, account: account, min_interval_minutes: 30) }

    it 'passes when no previous message recently' do
      expect(guard.check).to eq(action: :pass)
    end

    it 'reschedules when a previous delivery was sent < 30min ago' do
      create(:captain_lifecycle_delivery,
             account: account, captain_reservation: reservation,
             status: 'sent', sent_at: 10.minutes.ago, origin: 'scheduled_lifecycle')

      result = guard.check
      expect(result[:action]).to eq(:reschedule)
      # should fire approximately 30min after the previous sent_at
      expect(result[:fire_at]).to be_within(1.minute).of(10.minutes.ago + 30.minutes)
    end
  end
end
```

- [ ] **Step 2: Implement min_interval guard**

```ruby
# enterprise/app/services/captain/lifecycle/guards/min_interval.rb
class Captain::Lifecycle::Guards::MinInterval < Captain::Lifecycle::Guards::Base
  MAX_DELAY = 2.hours

  def check
    config = Captain::Lifecycle::Config.for_account(@account)
    interval = config.min_interval_minutes.to_i
    return pass if interval <= 0

    last_sent_at = Captain::Lifecycle::Delivery
                   .where(captain_reservation_id: @reservation.id,
                          status: 'sent',
                          origin: 'scheduled_lifecycle')
                   .maximum(:sent_at)
    return pass if last_sent_at.blank?

    earliest_allowed = last_sent_at + interval.minutes
    return pass if @delivery.fire_at >= earliest_allowed

    delay = earliest_allowed - @delivery.fire_at
    return skip('too_stale') if delay > MAX_DELAY

    reschedule(earliest_allowed)
  end
end
```

- [ ] **Step 3: Run min_interval spec to verify pass**

Run: `bundle exec rspec spec/enterprise/services/captain/lifecycle/guards/min_interval_spec.rb`
Expected: pass.

- [ ] **Step 4: Write failing spec for customer_replied**

```ruby
# spec/enterprise/services/captain/lifecycle/guards/customer_replied_spec.rb
require 'rails_helper'

RSpec.describe Captain::Lifecycle::Guards::CustomerReplied do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account) }
  let(:reservation) { create(:captain_reservation, account: account, contact: contact) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, contact: contact, inbox: inbox) }
  let(:delivery) do
    create(:captain_lifecycle_delivery,
           account: account, captain_reservation: reservation,
           conversation: conversation, inbox: inbox,
           fire_at: Time.current + 1.minute)
  end
  subject(:guard) { described_class.new(delivery) }

  context 'when guard disabled' do
    before { create(:captain_lifecycle_config, account: account, pause_on_customer_reply: false) }
    it('passes') { expect(guard.check).to eq(action: :pass) }
  end

  context 'when guard enabled (60 min window)' do
    before do
      create(:captain_lifecycle_config,
             account: account, pause_on_customer_reply: true, pause_on_customer_reply_within_minutes: 60)
    end

    it 'passes when no recent incoming messages' do
      expect(guard.check).to eq(action: :pass)
    end

    it 'reschedules when customer sent a message 10min ago' do
      create(:message, account: account, conversation: conversation,
                       message_type: 'incoming', created_at: 10.minutes.ago)

      result = guard.check
      expect(result[:action]).to eq(:reschedule)
    end
  end
end
```

- [ ] **Step 5: Implement customer_replied guard**

```ruby
# enterprise/app/services/captain/lifecycle/guards/customer_replied.rb
class Captain::Lifecycle::Guards::CustomerReplied < Captain::Lifecycle::Guards::Base
  MAX_DELAY = 2.hours

  def check
    config = Captain::Lifecycle::Config.for_account(@account)
    return pass unless config.pause_on_customer_reply

    window = config.pause_on_customer_reply_within_minutes.to_i.minutes
    conversation = resolve_conversation
    return pass if conversation.blank?

    last_incoming_at = conversation.messages
                                   .where(message_type: Message.message_types[:incoming])
                                   .maximum(:created_at)
    return pass if last_incoming_at.blank?

    wait_until = last_incoming_at + window
    return pass if @delivery.fire_at >= wait_until

    delay = wait_until - @delivery.fire_at
    return skip('too_stale') if delay > MAX_DELAY

    reschedule(wait_until)
  end

  private

  def resolve_conversation
    return @delivery.conversation if @delivery.conversation.present?

    inbox_id = @delivery.inbox_id || @reservation.unit&.concierge_inbox_id
    return nil if inbox_id.blank?

    @account.conversations
            .where(contact_id: @reservation.contact_id, inbox_id: inbox_id)
            .order(last_activity_at: :desc)
            .first
  end
end
```

- [ ] **Step 6: Run customer_replied spec to verify pass**

Run: `bundle exec rspec spec/enterprise/services/captain/lifecycle/guards/customer_replied_spec.rb`
Expected: pass.

- [ ] **Step 7: Commit**

```bash
git add enterprise/app/services/captain/lifecycle/guards/min_interval.rb enterprise/app/services/captain/lifecycle/guards/customer_replied.rb spec/enterprise/services/captain/lifecycle/guards/min_interval_spec.rb spec/enterprise/services/captain/lifecycle/guards/customer_replied_spec.rb
git commit -m "feat(lifecycle): add MinInterval and CustomerReplied guards"
```

---

## Task 15: Dispatcher service

Orchestrates guards → render → send. Called by the Sidekiq job.

**Files:**
- Create: `enterprise/app/services/captain/lifecycle/dispatcher.rb`
- Create: `spec/enterprise/services/captain/lifecycle/dispatcher_spec.rb`

- [ ] **Step 1: Write failing spec**

```ruby
# spec/enterprise/services/captain/lifecycle/dispatcher_spec.rb
require 'rails_helper'

RSpec.describe Captain::Lifecycle::Dispatcher do
  let(:account) { create(:account) }
  let(:unit) { create(:captain_unit, account: account, concierge_inbox: inbox) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account, name: 'João Silva', phone_number: '+5561999999999') }
  let(:reservation) do
    create(:captain_reservation,
           account: account, captain_unit: unit, contact: contact,
           suite_identifier: 'Alexa', check_in_at: 2.hours.from_now, check_out_at: 10.hours.from_now)
  end
  let(:rule) do
    create(:captain_lifecycle_rule,
           account: account, event: 'checkin.scheduled_at', offset_minutes: -10,
           message_body: 'Oi {{ customer.first_name }}, suíte {{ reservation.suite }}!')
  end
  let(:delivery) do
    create(:captain_lifecycle_delivery,
           account: account, captain_reservation: reservation,
           lifecycle_rule: rule, inbox: inbox, fire_at: 1.hour.from_now)
  end

  subject(:dispatcher) { described_class.new(delivery) }

  describe '#call' do
    context 'happy path' do
      before do
        allow_any_instance_of(Captain::Lifecycle::Dispatcher)
          .to receive(:send_message)
          .and_return(build_stubbed(:message, id: 42))
      end

      it 'renders the template and marks delivery sent' do
        dispatcher.call
        expect(delivery.reload.status).to eq('sent')
        expect(delivery.rendered_body).to include('João')
        expect(delivery.rendered_body).to include('Alexa')
      end

      it 'sets current_unit_id on conversation' do
        dispatcher.call
        expect(delivery.reload.conversation.custom_attributes['current_unit_id']).to eq(unit.id)
      end
    end

    context 'guard blocks with skip' do
      before { reservation.update!(status: 'cancelled') }

      it 'marks delivery skipped with reason' do
        dispatcher.call
        expect(delivery.reload.status).to eq('skipped')
        expect(delivery.skip_reason).to eq('reservation_cancelled')
      end
    end

    context 'guard blocks with reschedule' do
      it 'reschedules the delivery and does not send' do
        allow_any_instance_of(Captain::Lifecycle::Guards::QuietHours)
          .to receive(:check)
          .and_return(action: :reschedule, fire_at: 2.hours.from_now)

        expect(Captain::Lifecycle::DispatcherJob).to receive(:perform_at)
        dispatcher.call
        expect(delivery.reload.status).to eq('scheduled')
        expect(delivery.fire_at).to be_within(1.minute).of(2.hours.from_now)
      end
    end

    context 'not in scheduled state' do
      before { delivery.update!(status: 'cancelled') }

      it 'aborts without side effects' do
        dispatcher.call
        expect(delivery.reload.status).to eq('cancelled')
      end
    end
  end
end
```

- [ ] **Step 2: Run spec to verify failure**

Run: `bundle exec rspec spec/enterprise/services/captain/lifecycle/dispatcher_spec.rb`
Expected: FAIL — `uninitialized constant Captain::Lifecycle::Dispatcher`.

- [ ] **Step 3: Implement Dispatcher**

```ruby
# enterprise/app/services/captain/lifecycle/dispatcher.rb
class Captain::Lifecycle::Dispatcher
  GUARDS = [
    Captain::Lifecycle::Guards::ReservationActive,
    Captain::Lifecycle::Guards::OptOutLabel,
    Captain::Lifecycle::Guards::MaxPerReservation,
    Captain::Lifecycle::Guards::QuietHours,
    Captain::Lifecycle::Guards::MinInterval,
    Captain::Lifecycle::Guards::CustomerReplied
  ].freeze

  def initialize(delivery)
    @delivery = delivery
  end

  def call
    return unless @delivery.status == 'scheduled'

    guard_result = run_guards
    case guard_result[:action]
    when :skip
      @delivery.mark_skipped!(guard_result[:reason])
      return
    when :reschedule
      apply_reschedule(guard_result[:fire_at])
      return
    end

    rendered = render_template
    message = send_message(rendered)
    @delivery.mark_sent!(
      message: message,
      conversation: message.conversation,
      rendered_body: rendered
    )
  rescue StandardError => e
    Rails.logger.error("[LifecycleDispatcher] delivery #{@delivery.id} failed: #{e.class} #{e.message}")
    @delivery.mark_failed!(e.message)
    raise
  end

  private

  def run_guards
    GUARDS.each do |klass|
      result = klass.new(@delivery).check
      return result if result[:action] != :pass
    end
    { action: :pass }
  end

  def apply_reschedule(new_fire_at)
    @delivery.update!(fire_at: new_fire_at)
    Captain::Lifecycle::DispatcherJob.perform_at(new_fire_at, @delivery.id)
  end

  def render_template
    ctx = Captain::Lifecycle::ContextBuilder.build(@delivery.captain_reservation)
    rule = @delivery.lifecycle_rule
    Captain::PromptRenderer.render_string(rule.message_body.to_s, ctx)
  end

  def send_message(rendered_body)
    reservation = @delivery.captain_reservation
    inbox = reservation.unit&.concierge_inbox
    raise 'Concierge inbox not configured for unit' if inbox.blank?

    conversation = find_or_create_conversation(inbox, reservation)
    conversation.update!(custom_attributes: (conversation.custom_attributes || {}).merge(
      'current_unit_id' => reservation.captain_unit_id
    ))

    rule = @delivery.lifecycle_rule
    assistant = concierge_assistant_for(inbox)
    msg = Messages::MessageBuilder.new(
      assistant, conversation,
      { content: rendered_body, message_type: 'outgoing' }
    ).perform

    dispatch_interactive_if_needed(rule, reservation, rendered_body)
    msg
  end

  def find_or_create_conversation(inbox, reservation)
    contact = reservation.contact
    existing = inbox.conversations.where(contact_id: contact.id).order(last_activity_at: :desc).first
    return existing if existing.present?

    contact_inbox = ContactInbox.find_or_create_by!(
      contact: contact, inbox: inbox
    ) { |ci| ci.source_id = contact.phone_number.to_s.gsub(/\D/, '') }

    Conversation.create!(
      account_id: inbox.account_id,
      inbox_id: inbox.id,
      contact_id: contact.id,
      contact_inbox_id: contact_inbox.id
    )
  end

  def concierge_assistant_for(inbox)
    inbox.captain_inbox&.assistant
  end

  def dispatch_interactive_if_needed(rule, reservation, _rendered_body)
    return if rule.message_type == 'text' || rule.message_payload.blank?

    inbox = reservation.unit.concierge_inbox
    provider_service = inbox.channel.try(:create_messaging_service) || inbox.channel
    return unless provider_service.respond_to?(:send_interactive_message)

    payload = render_payload(rule.message_payload, reservation)
    provider_service.send_interactive_message(reservation.contact.phone_number, payload)
  end

  def render_payload(payload, reservation)
    ctx = Captain::Lifecycle::ContextBuilder.build(reservation)
    rendered = Captain::PromptRenderer.render_string(payload.to_json, ctx)
    JSON.parse(rendered)
  end
end
```

- [ ] **Step 4: Run spec to verify pass**

Run: `bundle exec rspec spec/enterprise/services/captain/lifecycle/dispatcher_spec.rb`
Expected: all examples pass.

- [ ] **Step 5: Commit**

```bash
git add enterprise/app/services/captain/lifecycle/dispatcher.rb spec/enterprise/services/captain/lifecycle/dispatcher_spec.rb
git commit -m "feat(lifecycle): add Dispatcher service with guards→render→send pipeline"
```

---

## Task 16: DispatcherJob (Sidekiq) — full implementation

Replaces the stub from Task 9 with a real job that calls the Dispatcher.

**Files:**
- Modify: `enterprise/app/jobs/captain/lifecycle/dispatcher_job.rb`
- Create: `spec/enterprise/jobs/captain/lifecycle/dispatcher_job_spec.rb`

- [ ] **Step 1: Write failing spec**

```ruby
# spec/enterprise/jobs/captain/lifecycle/dispatcher_job_spec.rb
require 'rails_helper'

RSpec.describe Captain::Lifecycle::DispatcherJob do
  let(:delivery) { create(:captain_lifecycle_delivery) }

  it 'calls Dispatcher#call' do
    dispatcher = instance_double(Captain::Lifecycle::Dispatcher)
    expect(Captain::Lifecycle::Dispatcher).to receive(:new).with(instance_of(Captain::Lifecycle::Delivery)).and_return(dispatcher)
    expect(dispatcher).to receive(:call)
    described_class.perform_now(delivery.id)
  end

  it 'silently skips missing delivery records' do
    expect { described_class.perform_now(-1) }.not_to raise_error
  end
end
```

- [ ] **Step 2: Run spec to verify failure**

Run: `bundle exec rspec spec/enterprise/jobs/captain/lifecycle/dispatcher_job_spec.rb`
Expected: FAIL — job is still a stub that does nothing.

- [ ] **Step 3: Replace the stub implementation**

```ruby
# enterprise/app/jobs/captain/lifecycle/dispatcher_job.rb
class Captain::Lifecycle::DispatcherJob < ApplicationJob
  queue_as :default
  retry_on StandardError, wait: :exponentially_longer, attempts: 3

  def perform(delivery_id)
    delivery = Captain::Lifecycle::Delivery.find_by(id: delivery_id)
    return if delivery.blank?

    Captain::Lifecycle::Dispatcher.new(delivery).call
  end
end
```

- [ ] **Step 4: Run spec to verify pass**

Run: `bundle exec rspec spec/enterprise/jobs/captain/lifecycle/dispatcher_job_spec.rb`
Expected: pass.

- [ ] **Step 5: Commit**

```bash
git add enterprise/app/jobs/captain/lifecycle/dispatcher_job.rb spec/enterprise/jobs/captain/lifecycle/dispatcher_job_spec.rb
git commit -m "feat(lifecycle): implement DispatcherJob"
```

---

## Task 17: Concierge Liquid context injection

Adds `{% render 'concierge' %}` / `{{ concierge.* }}` support to the Captain prompt rendering pipeline. Reads `conversation.custom_attributes['current_unit_id']` to resolve the unit and injects its config.

**Files:**
- Create: `enterprise/lib/captain/prompts/snippets/concierge.liquid`
- Create: `enterprise/lib/captain/prompts/concierge.liquid`
- Modify: `enterprise/app/models/concerns/agentable.rb`
- Create: `spec/enterprise/models/concerns/agentable_concierge_spec.rb`

- [ ] **Step 1: Write the concierge Liquid snippet**

```liquid
{%- comment -%}enterprise/lib/captain/prompts/snippets/concierge.liquid{%- endcomment -%}
# Concierge Context (unit: {{ concierge.unit_name }})
Persona: {{ concierge.persona_name }}

## Base de Conhecimento
{{ concierge.knowledge }}

## Variáveis Disponíveis
{% for pair in concierge.variables %}- {{ pair[0] }}: {{ pair[1] }}
{% endfor %}
```

- [ ] **Step 2: Write the default concierge orchestrator template**

```liquid
{%- comment -%}enterprise/lib/captain/prompts/concierge.liquid{%- endcomment -%}
Você é {{ concierge.persona_name }}, assistente virtual do {{ concierge.unit_name }}.

{% render 'concierge' %}

## Dados da Estadia Atual
- Suíte: {{ reservation.suite }}
- Check-in: {{ reservation.check_in_at }}
- Check-out: {{ reservation.check_out_at }}

## Como se comportar
(Escreva aqui tom, transparência de IA, regras de handoff, política de reclamações, etc.)
```

- [ ] **Step 3: Write failing spec for agentable extension**

```ruby
# spec/enterprise/models/concerns/agentable_concierge_spec.rb
require 'rails_helper'

RSpec.describe 'Agentable concierge context injection' do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:unit) do
    create(:captain_unit,
           account: account,
           name: 'Prime Águas Lindas',
           concierge_config: {
             'persona_name' => 'Sofia',
             'knowledge' => 'Hotel com café às 7h',
             'variables' => { 'wifi_password' => 'abc123' }
           })
  end
  let(:contact) { create(:contact, account: account, name: 'João Silva') }
  let(:conversation) do
    create(:conversation,
           account: account, inbox: inbox, contact: contact,
           custom_attributes: { 'current_unit_id' => unit.id })
  end
  let(:assistant) do
    create(:captain_assistant, account: account,
           orchestrator_prompt: '{{ concierge.persona_name }} in {{ concierge.unit_name }} knows: {{ concierge.knowledge }}')
  end

  it 'resolves concierge context from current_unit_id' do
    ctx = { conversation: { id: conversation.id } }.with_indifferent_access
    rendered = assistant.render_orchestrator_prompt(ctx)
    expect(rendered).to include('Sofia in Prime Águas Lindas')
    expect(rendered).to include('Hotel com café às 7h')
  end

  it 'falls back to empty strings when current_unit_id missing' do
    conversation.update!(custom_attributes: {})
    ctx = { conversation: { id: conversation.id } }.with_indifferent_access
    rendered = assistant.render_orchestrator_prompt(ctx)
    # should not raise; renders with empty persona_name defaulting
    expect(rendered).to be_a(String)
  end
end
```

- [ ] **Step 4: Run spec to verify failure**

Run: `bundle exec rspec spec/enterprise/models/concerns/agentable_concierge_spec.rb`
Expected: FAIL — `concierge.*` variables not in context.

- [ ] **Step 5: Update agentable concern to inject concierge context**

In `enterprise/app/models/concerns/agentable.rb`, find the `render_orchestrator_prompt` method (around line 15-35) and modify the enhancement block. The existing code builds `enhanced_context` from `state[:conversation]` and `state[:contact]`. Add a concierge branch before `ctx = enhanced_context.with_indifferent_access`:

```ruby
      enhanced_context = enhanced_context.merge(
        conversation: conversation_data,
        contact: contact_data,
        concierge: resolve_concierge_context(conversation_data),
        reservation: resolve_reservation_context(conversation_data)
      )
```

And add two private methods at the bottom of the concern (above any existing `private` methods or in a new private block):

```ruby
    def resolve_concierge_context(conversation_data)
      unit = resolve_current_unit(conversation_data)
      return default_concierge_context if unit.blank?

      {
        'persona_name' => unit.concierge_persona_name,
        'unit_name' => unit.name.to_s,
        'knowledge' => unit.concierge_knowledge,
        'variables' => unit.concierge_variables
      }
    end

    def resolve_reservation_context(conversation_data)
      conv = lookup_conversation(conversation_data)
      return {} if conv.blank?

      reservation = conv.account.captain_reservations
                        .where(contact_id: conv.contact_id)
                        .order(created_at: :desc)
                        .first
      return {} if reservation.blank?

      Captain::Lifecycle::ContextBuilder.build(reservation).fetch('reservation', {})
    end

    def resolve_current_unit(conversation_data)
      conv = lookup_conversation(conversation_data)
      return nil if conv.blank?

      unit_id = conv.custom_attributes.to_h['current_unit_id']
      return nil if unit_id.blank?

      Captain::Unit.find_by(id: unit_id)
    end

    def lookup_conversation(conversation_data)
      id = conversation_data.is_a?(Hash) ? (conversation_data[:id] || conversation_data['id']) : nil
      Conversation.find_by(id: id)
    end

    def default_concierge_context
      { 'persona_name' => 'Sofia', 'unit_name' => '', 'knowledge' => '', 'variables' => {} }
    end
```

- [ ] **Step 6: Run spec to verify pass**

Run: `bundle exec rspec spec/enterprise/models/concerns/agentable_concierge_spec.rb`
Expected: pass.

- [ ] **Step 7: Run the broader agentable/assistant spec to catch regressions**

Run: `bundle exec rspec spec/enterprise/models/captain/assistant_spec.rb 2>&1 | tail -20`
Expected: all still pass (existing tests do not depend on `concierge.*`).

- [ ] **Step 8: Commit**

```bash
git add enterprise/lib/captain/prompts/snippets/concierge.liquid enterprise/lib/captain/prompts/concierge.liquid enterprise/app/models/concerns/agentable.rb spec/enterprise/models/concerns/agentable_concierge_spec.rb
git commit -m "feat(lifecycle): inject concierge context into Captain orchestrator prompt"
```

---

## Task 18: End-to-end integration spec

Validates the full flow: create rule → create reservation → job gets enqueued → time-travel → job runs → guards pass → message sent → delivery logged.

**Files:**
- Create: `spec/enterprise/integration/captain/lifecycle_flow_spec.rb`

- [ ] **Step 1: Write the integration spec**

```ruby
# spec/enterprise/integration/captain/lifecycle_flow_spec.rb
require 'rails_helper'

RSpec.describe 'Captain::Lifecycle end-to-end flow', :freeze_time do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:unit) do
    create(:captain_unit, account: account, name: 'Águas Lindas',
                          concierge_inbox: inbox,
                          concierge_config: {
                            'persona_name' => 'Sofia',
                            'variables' => { 'wifi_password' => 'hotel1001' }
                          })
  end
  let(:captain_inbox) do
    create(:captain_inbox, account: account, inbox: inbox,
                           assistant: create(:captain_assistant, account: account))
  end
  let(:contact) { create(:contact, account: account, name: 'Maria Teste', phone_number: '+5561988887777') }

  before do
    captain_inbox
    Sidekiq::Testing.inline! if defined?(Sidekiq::Testing)
  end

  it 'schedules, dispatches, and logs a delivery through the full pipeline' do
    # 1. Create a rule
    rule = create(:captain_lifecycle_rule,
                  account: account,
                  event: 'checkin.scheduled_at',
                  offset_minutes: -10,
                  message_body: 'Oi {{ customer.first_name }}! Wi-fi: {{ hotel.wifi_password }}')

    # 2. Create a reservation with check_in 2 hours out
    reservation = create(:captain_reservation,
                         account: account, captain_unit: unit, contact: contact,
                         suite_identifier: 'Alexa',
                         check_in_at: 2.hours.from_now,
                         check_out_at: 10.hours.from_now)

    # 3. Delivery was scheduled
    delivery = Captain::Lifecycle::Delivery.last
    expect(delivery).not_to be_nil
    expect(delivery.status).to eq('scheduled')
    expect(delivery.lifecycle_rule_id).to eq(rule.id)
    expect(delivery.fire_at).to be_within(1.second).of(reservation.check_in_at - 10.minutes)

    # 4. Stub WuzAPI at the provider level to avoid real HTTP
    allow_any_instance_of(Whatsapp::Providers::WuzapiService)
      .to receive(:send_message).and_return({ 'Id' => 'stub-msg' })

    # 5. Time-travel to fire_at and run the job
    travel_to(delivery.fire_at) do
      Captain::Lifecycle::DispatcherJob.perform_now(delivery.id)
    end

    # 6. Delivery is now sent
    delivery.reload
    expect(delivery.status).to eq('sent')
    expect(delivery.rendered_body).to include('Maria')
    expect(delivery.rendered_body).to include('hotel1001')
    expect(delivery.sent_at).to be_present
    expect(delivery.conversation_id).to be_present
    expect(delivery.message_id).to be_present
  end

  it 'cancels pending deliveries when reservation is cancelled' do
    create(:captain_lifecycle_rule,
           account: account,
           event: 'checkin.scheduled_at',
           offset_minutes: -10,
           message_body: 'Oi')

    reservation = create(:captain_reservation,
                         account: account, captain_unit: unit, contact: contact,
                         check_in_at: 2.hours.from_now,
                         check_out_at: 10.hours.from_now)
    delivery = Captain::Lifecycle::Delivery.last
    expect(delivery.status).to eq('scheduled')

    reservation.update!(status: 'cancelled')
    expect(delivery.reload.status).to eq('cancelled')
  end

  it 'respects the max-5 cap' do
    5.times { |i|
      create(:captain_lifecycle_rule,
             account: account,
             name: "rule-#{i}",
             event: 'reservation.confirmed',
             offset_minutes: i,
             message_body: "msg #{i}")
    }
    create(:captain_lifecycle_rule,
           account: account,
           name: 'rule-6',
           event: 'reservation.confirmed',
           offset_minutes: 10,
           message_body: 'msg 6')

    # Stub send so first 5 succeed
    allow_any_instance_of(Captain::Lifecycle::Dispatcher)
      .to receive(:send_message).and_return(build_stubbed(:message, id: 1))

    reservation = create(:captain_reservation,
                         account: account, captain_unit: unit, contact: contact,
                         check_in_at: 2.hours.from_now,
                         check_out_at: 10.hours.from_now)

    # Fire all 6 scheduled jobs
    Captain::Lifecycle::Delivery.scheduled.each do |d|
      Captain::Lifecycle::DispatcherJob.perform_now(d.id)
    end

    statuses = Captain::Lifecycle::Delivery.where(captain_reservation: reservation).pluck(:status)
    expect(statuses.count('sent')).to eq(5)
    expect(statuses.count('skipped')).to eq(1)
    skipped = Captain::Lifecycle::Delivery.where(captain_reservation: reservation, status: 'skipped').first
    expect(skipped.skip_reason).to eq('max_reached')
  end
end
```

- [ ] **Step 2: Run the integration spec**

Run: `bundle exec rspec spec/enterprise/integration/captain/lifecycle_flow_spec.rb`
Expected: all 3 examples pass. If any fail, fix the underlying unit that owns the failure — do not patch the integration spec to hide bugs.

- [ ] **Step 3: Run full lifecycle test suite**

Run: `bundle exec rspec spec/enterprise/services/captain/lifecycle/ spec/enterprise/models/captain/lifecycle/ spec/enterprise/jobs/captain/lifecycle/ spec/enterprise/integration/captain/`
Expected: every example passes. This is the regression gate before commit.

- [ ] **Step 4: Commit**

```bash
git add spec/enterprise/integration/captain/lifecycle_flow_spec.rb
git commit -m "test(lifecycle): add end-to-end integration spec for scheduler→dispatch→send flow"
```

---

## Task 19: Seed for development / smoke script

A runnable rails script that sets up a test account + unit + rule + reservation so the developer can exercise the pipeline from `rails console` or `rails runner`.

**Files:**
- Create: `db/seeds/captain_lifecycle_demo.rb`

- [ ] **Step 1: Write the seed script**

```ruby
# db/seeds/captain_lifecycle_demo.rb
# Run with: bundle exec rails runner db/seeds/captain_lifecycle_demo.rb
#
# Creates a demo rule + reservation and leaves the delivery scheduled
# so the engineer can inspect it, fast-forward, or trigger manually.

account = Account.first || raise('No Account exists; create one first')
unit = account.captain_units.first || raise('No Captain::Unit exists; create one first')
inbox = unit.inboxes.first || raise('Unit has no inboxes')

# Ensure unit has concierge config
unit.update!(
  concierge_inbox_id: inbox.id,
  concierge_config: {
    'persona_name' => 'Sofia',
    'knowledge' => "## Sobre\nHotel exemplo para teste de lifecycle.\n## Wifi\nSenha: demo123\n",
    'variables' => { 'wifi_password' => 'demo123' }
  }
)

rule = Captain::Lifecycle::Rule.create!(
  account: account,
  name: 'DEMO lembrete 10min antes check-in',
  enabled: true,
  event: 'checkin.scheduled_at',
  offset_minutes: -10,
  filters: {},
  message_type: 'text',
  message_body: 'Oi {{ customer.first_name }}! Sua {{ reservation.suite }} tá pronta. Wifi: {{ hotel.wifi_password }}'
)

contact = account.contacts.first_or_create!(
  name: 'Cliente Demo',
  phone_number: '+5561900000000',
  email: 'demo@example.com'
)

reservation = Captain::Reservation.create!(
  account: account,
  captain_unit: unit,
  contact: contact,
  suite_identifier: 'Alexa',
  status: :scheduled,
  total_amount: 160.0,
  check_in_at: 30.minutes.from_now,
  check_out_at: 8.hours.from_now,
  inbox: inbox,
  metadata: { 'permanencia' => 'Pernoite' }
)

delivery = Captain::Lifecycle::Delivery.where(captain_reservation_id: reservation.id).last
puts '--- DEMO CREATED ---'
puts "Rule:        #{rule.id} — #{rule.name}"
puts "Reservation: #{reservation.id} (check_in_at = #{reservation.check_in_at})"
puts "Delivery:    #{delivery&.id} status=#{delivery&.status} fire_at=#{delivery&.fire_at}"
puts
puts 'To fire now:'
puts "  Captain::Lifecycle::DispatcherJob.perform_now(#{delivery&.id})"
```

- [ ] **Step 2: Run the seed to verify it works**

Run: `bundle exec rails runner db/seeds/captain_lifecycle_demo.rb`
Expected output (values vary):
```
--- DEMO CREATED ---
Rule:        1 — DEMO lembrete 10min antes check-in
Reservation: 42 (check_in_at = 2026-04-15 XX:XX:XX ...)
Delivery:    1 status=scheduled fire_at=2026-04-15 XX:XX:XX ...

To fire now:
  Captain::Lifecycle::DispatcherJob.perform_now(1)
```

- [ ] **Step 3: Commit**

```bash
git add db/seeds/captain_lifecycle_demo.rb
git commit -m "chore(lifecycle): add demo seed script for manual pipeline testing"
```

---

## Task 20: Rubocop + ensure no style regressions

Run rubocop on everything new. Fix any offenses inline (no `rubocop:disable` unless justified).

- [ ] **Step 1: Run rubocop on all new/modified files**

```bash
bundle exec rubocop \
  enterprise/app/models/captain/lifecycle.rb \
  enterprise/app/models/captain/lifecycle/ \
  enterprise/app/services/captain/lifecycle/ \
  enterprise/app/jobs/captain/lifecycle/ \
  enterprise/app/models/concerns/agentable.rb \
  enterprise/app/models/captain/unit.rb \
  enterprise/app/models/captain/reservation.rb \
  app/services/wuzapi/client.rb \
  app/services/whatsapp/providers/wuzapi_service.rb
```
Expected: no offenses.

- [ ] **Step 2: If offenses found, auto-fix where safe**

```bash
bundle exec rubocop -a <files>
```
Then re-run without `-a` to confirm clean.

- [ ] **Step 3: Run full backend spec suite one final time**

```bash
bundle exec rspec \
  spec/enterprise/models/captain/lifecycle \
  spec/enterprise/services/captain/lifecycle \
  spec/enterprise/jobs/captain/lifecycle \
  spec/enterprise/integration/captain \
  spec/enterprise/models/captain/reservation_lifecycle_hooks_spec.rb \
  spec/enterprise/models/captain/unit_concierge_spec.rb \
  spec/enterprise/models/concerns/agentable_concierge_spec.rb \
  spec/services/wuzapi/client_interactive_spec.rb \
  spec/services/whatsapp/providers/wuzapi_interactive_spec.rb
```
Expected: 100% green.

- [ ] **Step 4: Commit any fixes**

```bash
git add -u
git commit -m "style(lifecycle): rubocop cleanup on new lifecycle files" || true
```

---

## Validação final

Ao final do plano, tudo deve passar:

```bash
bundle exec rubocop
bundle exec rspec spec/enterprise/models/captain/lifecycle spec/enterprise/services/captain/lifecycle spec/enterprise/jobs/captain/lifecycle spec/enterprise/integration/captain
```

Critérios de conclusão:

- [ ] Migrations aplicam limpo em banco zerado
- [ ] Todos os specs novos passam
- [ ] Seed de demo cria um cenário funcional ponta-a-ponta
- [ ] `rails runner` consegue disparar manualmente um delivery e ver a mensagem chegando no WuzAPI (stub ou real)
- [ ] Rubocop 100% clean nos arquivos novos
- [ ] Nenhum spec existente (Jasmine, reservas, outros) foi quebrado pelo hooks novos

## Fora de escopo deste plano (ficam pra follow-ups)

- **Plano Fase B — Admin UI "Jornada do Cliente"**: wizard de 4 passos, editor de mensagem com autocomplete, tabs de configurações e histórico, templates prontos. Depende deste plano estar concluído e validado.
- Detecção heurística de `checkin.detected` / `checkout.detected` (backlog)
- Dashboard analítico de funil (backlog)
- Sincronização de templates prontos via seed (backlog)
- Observabilidade Prometheus (backlog)
