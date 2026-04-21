# Jornada do Cliente — UI (Fase B) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Entregar a aba "Jornada do Cliente" no menu Captain — 3 tabs (Regras, Configurações, Histórico) — consumindo o backend de lifecycle automation já shippado em `enterprise/app/models/captain/lifecycle/` e `enterprise/app/services/captain/lifecycle/`.

**Architecture:** REST endpoints novos em `enterprise/app/controllers/api/v1/accounts/captain/` (3 controllers + extensão do `UnitsController` pra concierge config), jbuilder views, Pundit policies, clientes API Vue + Pinia stores via `storeFactory`, rota-pai com `TabBar` + 3 children routes, páginas Vue em `components-next` seguindo o padrão de `captain/reservations`. Multilíngue obrigatório (en + pt_BR).

**Tech Stack:** Rails 7.1 + Pundit + jbuilder, Vue 3 `<script setup>` + Pinia (via `storeFactory`), `ApiClient` base, `TabBar.vue`, `PageLayout.vue`, `Input/TextArea/Button/Checkbox` de `components-next`, vue-i18n, RSpec request specs, Vitest.

---

## Pré-requisitos de contexto

Antes de começar, **leia** estes 3 arquivos:
- `docs/superpowers/specs/2026-04-15-jornada-do-cliente-design.md` — seção 9 é o escopo; seções 4, 5 e 8 explicam domínio (eventos, variáveis Liquid, schema)
- `docs/superpowers/plans/2026-04-15-jornada-do-cliente-backend-handoff.md` — mapa do que o backend já entregou + 9 gotchas
- `CLAUDE.md` da raiz — convenção `fazer.ai` minúsculo, branding, pnpm obrigatório

**Gotchas relevantes pra UI** (do handoff):
1. Reservation hook `after_create_commit :schedule_lifecycle_rules` dispara ao criar reserva — specs que testam endpoint de deliveries podem criar deliveries "fantasma". Stubbar `Captain::Lifecycle::Scheduler.schedule_for` nos specs ou criar delivery diretamente via `Delivery.create!`.
2. `belongs_to` top-level dentro de `Captain::Lifecycle::*` precisa `class_name: '::Conversation'` etc — já resolvido nos models, só não refatorar.
3. `captain_unit` factory aceita `create(:captain_unit)` direto (fix em `325f05c3e`).
4. `Captain::Reservation` usa associação `unit:`, não `captain_unit:`.

---

## Estrutura de arquivos

**Backend (novos):**

| Arquivo | Responsabilidade |
|---|---|
| `app/models/account.rb` | Adicionar 3 `has_many` pras novas tabelas lifecycle |
| `enterprise/app/policies/captain/lifecycle/rule_policy.rb` | Pundit — admin pode CRUD, agent só read |
| `enterprise/app/policies/captain/lifecycle/config_policy.rb` | Pundit — só admin |
| `enterprise/app/policies/captain/lifecycle/delivery_policy.rb` | Pundit — admin + agent podem ler |
| `config/routes.rb` | 3 resources dentro do `namespace :captain` |
| `enterprise/app/controllers/api/v1/accounts/captain/lifecycle_rules_controller.rb` | CRUD de regras |
| `enterprise/app/controllers/api/v1/accounts/captain/lifecycle_configs_controller.rb` | `show`/`update` do singleton `Config.for_account` |
| `enterprise/app/controllers/api/v1/accounts/captain/lifecycle_deliveries_controller.rb` | `index` paginada + `show` com `rendered_body` |
| `enterprise/app/controllers/api/v1/accounts/captain/units_controller.rb` | Adicionar action `update_concierge` + permit de `concierge_inbox_id` e `concierge_config` |
| `enterprise/app/views/api/v1/models/captain/_lifecycle_rule.json.jbuilder` | Partial |
| `enterprise/app/views/api/v1/models/captain/_lifecycle_config.json.jbuilder` | Partial |
| `enterprise/app/views/api/v1/models/captain/_lifecycle_delivery.json.jbuilder` | Partial |
| `enterprise/app/views/api/v1/accounts/captain/lifecycle_rules/{index,show,create,update}.json.jbuilder` | Templates |
| `enterprise/app/views/api/v1/accounts/captain/lifecycle_configs/{show,update}.json.jbuilder` | Templates |
| `enterprise/app/views/api/v1/accounts/captain/lifecycle_deliveries/{index,show}.json.jbuilder` | Templates |

**Frontend (novos):**

| Arquivo | Responsabilidade |
|---|---|
| `app/javascript/dashboard/api/captain/lifecycleRules.js` | Cliente REST |
| `app/javascript/dashboard/api/captain/lifecycleConfig.js` | Cliente REST (singleton) |
| `app/javascript/dashboard/api/captain/lifecycleDeliveries.js` | Cliente REST |
| `app/javascript/dashboard/store/captain/lifecycleRules.js` | Pinia store via factory |
| `app/javascript/dashboard/store/captain/lifecycleConfig.js` | Pinia store (singleton, get/update manuais) |
| `app/javascript/dashboard/store/captain/lifecycleDeliveries.js` | Pinia store via factory |
| `app/javascript/dashboard/store/index.js` | Registrar 3 novos módulos |
| `app/javascript/dashboard/routes/dashboard/captain/lifecycle/Index.vue` | Pai com `TabBar` + `<router-view />` |
| `app/javascript/dashboard/routes/dashboard/captain/lifecycle/Rules.vue` | Tab 1 — lista + templates + botão "Nova regra" |
| `app/javascript/dashboard/routes/dashboard/captain/lifecycle/Settings.vue` | Tab 2 — guards + Sofia por unidade |
| `app/javascript/dashboard/routes/dashboard/captain/lifecycle/History.vue` | Tab 3 — tabela paginada + modal preview |
| `app/javascript/dashboard/routes/dashboard/captain/lifecycle/components/RuleWizardDialog.vue` | Wizard 4 passos criar/editar regra |
| `app/javascript/dashboard/routes/dashboard/captain/lifecycle/components/MessageEditor.vue` | Textarea + autocomplete de variáveis + botões |
| `app/javascript/dashboard/routes/dashboard/captain/lifecycle/components/ConciergeUnitCard.vue` | Card expansível por unidade dentro de Settings |
| `app/javascript/dashboard/routes/dashboard/captain/lifecycle/components/DeliveryPreviewModal.vue` | Modal com `rendered_body` |
| `app/javascript/dashboard/routes/dashboard/captain/lifecycle/constants.js` | `EVENTS`, `MESSAGE_TYPES`, templates prontos |
| `app/javascript/dashboard/routes/dashboard/captain/captain.routes.js` | Adicionar 4 rotas (1 pai + 3 filhas) |
| `app/javascript/dashboard/components-next/sidebar/Sidebar.vue` | Entrada nova na seção Captain |
| `app/javascript/dashboard/i18n/locale/en/captain.json` | Chaves `CAPTAIN_LIFECYCLE.*` |
| `app/javascript/dashboard/i18n/locale/pt_BR/captain.json` | Idem |
| `app/javascript/dashboard/i18n/locale/en/settings.json` | `SIDEBAR.CAPTAIN_LIFECYCLE` |
| `app/javascript/dashboard/i18n/locale/pt_BR/settings.json` | Idem |

---

## Task 1: Associações no Account model

**Files:**
- Modify: `app/models/account.rb` (linha ~99, depois de `captain_reservations`)

- [ ] **Step 1: Escrever spec falhando**

Append ao final de `spec/models/account_spec.rb`:

```ruby
  describe 'captain lifecycle associations' do
    it { is_expected.to have_many(:captain_lifecycle_rules).class_name('Captain::Lifecycle::Rule') }
    it { is_expected.to have_many(:captain_lifecycle_deliveries).class_name('Captain::Lifecycle::Delivery') }
    it { is_expected.to have_one(:captain_lifecycle_config).class_name('Captain::Lifecycle::Config') }
  end
```

- [ ] **Step 2: Rodar e ver falhar**

```bash
eval "$(rbenv init - zsh)" && rbenv shell 3.4.4 && bundle exec rspec spec/models/account_spec.rb -e "captain lifecycle associations"
```
Esperado: FAIL com `expected Account to have many captain_lifecycle_rules`.

- [ ] **Step 3: Implementar**

Em `app/models/account.rb`, logo após a linha `has_many :captain_reservations, ...`:

```ruby
  has_many :captain_lifecycle_rules, class_name: 'Captain::Lifecycle::Rule', dependent: :destroy
  has_many :captain_lifecycle_deliveries, class_name: 'Captain::Lifecycle::Delivery', dependent: :destroy
  has_one :captain_lifecycle_config, class_name: 'Captain::Lifecycle::Config', dependent: :destroy
```

- [ ] **Step 4: Rodar e ver passar**

```bash
bundle exec rspec spec/models/account_spec.rb -e "captain lifecycle associations"
```
Esperado: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/models/account.rb spec/models/account_spec.rb
git commit -m "feat(lifecycle): add Account associations for lifecycle models"
```

---

## Task 2: Pundit policies

**Files:**
- Create: `enterprise/app/policies/captain/lifecycle/rule_policy.rb`
- Create: `enterprise/app/policies/captain/lifecycle/config_policy.rb`
- Create: `enterprise/app/policies/captain/lifecycle/delivery_policy.rb`
- Create: `spec/enterprise/policies/captain/lifecycle/rule_policy_spec.rb`

- [ ] **Step 1: Spec falhando**

Criar `spec/enterprise/policies/captain/lifecycle/rule_policy_spec.rb`:

```ruby
require 'rails_helper'

RSpec.describe Captain::Lifecycle::RulePolicy do
  subject { described_class }

  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:admin_context) { { user: admin, account: account, account_user: admin.account_users.first } }
  let(:agent_context) { { user: agent, account: account, account_user: agent.account_users.first } }
  let(:record) { Captain::Lifecycle::Rule.new(account: account) }

  permissions :index?, :show? do
    it { is_expected.to permit(admin_context, record) }
    it { is_expected.to permit(agent_context, record) }
  end

  permissions :create?, :update?, :destroy? do
    it { is_expected.to permit(admin_context, record) }
    it { is_expected.not_to permit(agent_context, record) }
  end
end
```

- [ ] **Step 2: Rodar e falhar**

```bash
bundle exec rspec spec/enterprise/policies/captain/lifecycle/rule_policy_spec.rb
```
Esperado: FAIL `uninitialized constant Captain::Lifecycle::RulePolicy`.

- [ ] **Step 3: Implementar as 3 policies**

Criar `enterprise/app/policies/captain/lifecycle/rule_policy.rb`:

```ruby
class Captain::Lifecycle::RulePolicy < ApplicationPolicy
  def index?
    true
  end

  def show?
    true
  end

  def create?
    @account_user.administrator?
  end

  def update?
    @account_user.administrator?
  end

  def destroy?
    @account_user.administrator?
  end
end
```

Criar `enterprise/app/policies/captain/lifecycle/config_policy.rb`:

```ruby
class Captain::Lifecycle::ConfigPolicy < ApplicationPolicy
  def show?
    true
  end

  def update?
    @account_user.administrator?
  end
end
```

Criar `enterprise/app/policies/captain/lifecycle/delivery_policy.rb`:

```ruby
class Captain::Lifecycle::DeliveryPolicy < ApplicationPolicy
  def index?
    true
  end

  def show?
    true
  end
end
```

- [ ] **Step 4: Rodar e passar**

```bash
bundle exec rspec spec/enterprise/policies/captain/lifecycle/rule_policy_spec.rb
```
Esperado: PASS (5 examples).

- [ ] **Step 5: Commit**

```bash
git add enterprise/app/policies/captain/lifecycle spec/enterprise/policies/captain/lifecycle
git commit -m "feat(lifecycle): add Pundit policies for rule/config/delivery"
```

---

## Task 3: Rotas REST

**Files:**
- Modify: `config/routes.rb` (dentro do `namespace :captain`, linha ~60)

- [ ] **Step 1: Spec falhando**

Criar `spec/routing/captain_lifecycle_routes_spec.rb`:

```ruby
require 'rails_helper'

RSpec.describe 'Captain lifecycle routes', type: :routing do
  it 'routes GET /api/v1/accounts/1/captain/lifecycle_rules' do
    expect(get: '/api/v1/accounts/1/captain/lifecycle_rules')
      .to route_to(controller: 'api/v1/accounts/captain/lifecycle_rules', action: 'index', account_id: '1')
  end

  it 'routes GET /api/v1/accounts/1/captain/lifecycle_config' do
    expect(get: '/api/v1/accounts/1/captain/lifecycle_config')
      .to route_to(controller: 'api/v1/accounts/captain/lifecycle_configs', action: 'show', account_id: '1')
  end

  it 'routes GET /api/v1/accounts/1/captain/lifecycle_deliveries' do
    expect(get: '/api/v1/accounts/1/captain/lifecycle_deliveries')
      .to route_to(controller: 'api/v1/accounts/captain/lifecycle_deliveries', action: 'index', account_id: '1')
  end

  it 'routes PATCH /api/v1/accounts/1/captain/units/5/concierge' do
    expect(patch: '/api/v1/accounts/1/captain/units/5/concierge')
      .to route_to(controller: 'api/v1/accounts/captain/units', action: 'update_concierge', account_id: '1', id: '5')
  end
end
```

- [ ] **Step 2: Rodar e falhar**

```bash
bundle exec rspec spec/routing/captain_lifecycle_routes_spec.rb
```
Esperado: FAIL (nenhuma das rotas existe).

- [ ] **Step 3: Adicionar rotas**

Em `config/routes.rb`, dentro do `namespace :captain` (procure `resources :units`), adicionar logo antes de `resources :units`:

```ruby
            resources :lifecycle_rules
            resource :lifecycle_config, only: [:show, :update], controller: 'lifecycle_configs'
            resources :lifecycle_deliveries, only: [:index, :show]
```

E alterar `resources :units` pra:

```ruby
            resources :units do
              member do
                patch :concierge, action: :update_concierge
              end
            end
```

- [ ] **Step 4: Rodar e passar**

```bash
bundle exec rspec spec/routing/captain_lifecycle_routes_spec.rb
```
Esperado: PASS (4 examples).

- [ ] **Step 5: Commit**

```bash
git add config/routes.rb spec/routing/captain_lifecycle_routes_spec.rb
git commit -m "feat(lifecycle): add REST routes for rules, config, deliveries, concierge"
```

---

## Task 4: LifecycleRulesController + jbuilders

**Files:**
- Create: `enterprise/app/controllers/api/v1/accounts/captain/lifecycle_rules_controller.rb`
- Create: `enterprise/app/views/api/v1/models/captain/_lifecycle_rule.json.jbuilder`
- Create: `enterprise/app/views/api/v1/accounts/captain/lifecycle_rules/index.json.jbuilder`
- Create: `enterprise/app/views/api/v1/accounts/captain/lifecycle_rules/show.json.jbuilder`
- Create: `enterprise/app/views/api/v1/accounts/captain/lifecycle_rules/create.json.jbuilder`
- Create: `enterprise/app/views/api/v1/accounts/captain/lifecycle_rules/update.json.jbuilder`
- Create: `spec/enterprise/controllers/api/v1/accounts/captain/lifecycle_rules_controller_spec.rb`
- Create: `spec/factories/captain/lifecycle/rule.rb`

- [ ] **Step 1: Factory**

Criar `spec/factories/captain/lifecycle/rule.rb`:

```ruby
FactoryBot.define do
  factory :captain_lifecycle_rule, class: 'Captain::Lifecycle::Rule' do
    account
    sequence(:name) { |n| "Rule #{n}" }
    enabled { true }
    event { 'checkin.scheduled_at' }
    offset_minutes { -10 }
    filters { {} }
    message_type { 'text' }
    message_body { 'Olá {{ customer.first_name }}!' }
    priority { 50 }
  end
end
```

- [ ] **Step 2: Spec falhando**

Criar `spec/enterprise/controllers/api/v1/accounts/captain/lifecycle_rules_controller_spec.rb`:

```ruby
require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::Captain::LifecycleRules', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:other_account) { create(:account) }

  def json_response
    JSON.parse(response.body, symbolize_names: true)
  end

  describe 'GET /api/v1/accounts/:account_id/captain/lifecycle_rules' do
    it 'returns 401 when unauthenticated' do
      get "/api/v1/accounts/#{account.id}/captain/lifecycle_rules"
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns the account rules (and not others)' do
      create_list(:captain_lifecycle_rule, 2, account: account)
      create(:captain_lifecycle_rule, account: other_account)

      get "/api/v1/accounts/#{account.id}/captain/lifecycle_rules",
          headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(json_response[:payload].length).to eq(2)
    end
  end

  describe 'POST /api/v1/accounts/:account_id/captain/lifecycle_rules' do
    let(:valid_params) do
      {
        rule: {
          name: 'Lembrete pré check-in',
          event: 'checkin.scheduled_at',
          offset_minutes: -10,
          message_type: 'text',
          message_body: 'Oi {{ customer.first_name }}',
          filters: { unit_ids: [1] },
          enabled: true
        }
      }
    end

    it 'blocks agents' do
      post "/api/v1/accounts/#{account.id}/captain/lifecycle_rules",
           params: valid_params, headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    it 'creates for admin' do
      post "/api/v1/accounts/#{account.id}/captain/lifecycle_rules",
           params: valid_params, headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
      expect(json_response[:name]).to eq('Lembrete pré check-in')
      expect(Captain::Lifecycle::Rule.where(account: account).count).to eq(1)
    end
  end

  describe 'PATCH /api/v1/accounts/:account_id/captain/lifecycle_rules/:id' do
    let(:rule) { create(:captain_lifecycle_rule, account: account, name: 'old') }

    it 'updates for admin' do
      patch "/api/v1/accounts/#{account.id}/captain/lifecycle_rules/#{rule.id}",
            params: { rule: { name: 'new' } },
            headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
      expect(rule.reload.name).to eq('new')
    end
  end

  describe 'DELETE /api/v1/accounts/:account_id/captain/lifecycle_rules/:id' do
    it 'destroys for admin' do
      rule = create(:captain_lifecycle_rule, account: account)
      delete "/api/v1/accounts/#{account.id}/captain/lifecycle_rules/#{rule.id}",
             headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
      expect(Captain::Lifecycle::Rule.where(id: rule.id)).to be_empty
    end
  end
end
```

- [ ] **Step 3: Rodar e falhar**

```bash
bundle exec rspec spec/enterprise/controllers/api/v1/accounts/captain/lifecycle_rules_controller_spec.rb
```
Esperado: FAIL — `uninitialized constant`.

- [ ] **Step 4: Implementar controller**

Criar `enterprise/app/controllers/api/v1/accounts/captain/lifecycle_rules_controller.rb`:

```ruby
class Api::V1::Accounts::Captain::LifecycleRulesController < Api::V1::Accounts::BaseController
  before_action :current_account
  before_action -> { check_authorization(Captain::Lifecycle::Rule) }
  before_action :set_rule, only: [:show, :update, :destroy]

  def index
    @rules = Current.account.captain_lifecycle_rules.order(priority: :asc, id: :desc)
  end

  def show; end

  def create
    @rule = Current.account.captain_lifecycle_rules.create!(
      rule_params.merge(created_by_user: Current.user)
    )
    render 'api/v1/accounts/captain/lifecycle_rules/show'
  end

  def update
    @rule.update!(rule_params)
    render 'api/v1/accounts/captain/lifecycle_rules/show'
  end

  def destroy
    @rule.destroy!
    head :no_content
  end

  private

  def set_rule
    @rule = Current.account.captain_lifecycle_rules.find(params[:id])
  end

  def rule_params
    params.require(:rule).permit(
      :name, :description, :enabled, :event, :offset_minutes,
      :message_type, :message_body, :priority,
      filters: {},
      message_payload: {}
    )
  end
end
```

- [ ] **Step 5: Implementar jbuilder partial**

Criar `enterprise/app/views/api/v1/models/captain/_lifecycle_rule.json.jbuilder`:

```jbuilder
json.id resource.id
json.account_id resource.account_id
json.name resource.name
json.description resource.description
json.enabled resource.enabled
json.event resource.event
json.offset_minutes resource.offset_minutes
json.filters resource.filters || {}
json.message_type resource.message_type
json.message_body resource.message_body
json.message_payload resource.message_payload
json.priority resource.priority
json.created_by_user_id resource.created_by_user_id
json.created_at resource.created_at&.iso8601
json.updated_at resource.updated_at&.iso8601
```

- [ ] **Step 6: Templates**

Criar `enterprise/app/views/api/v1/accounts/captain/lifecycle_rules/index.json.jbuilder`:

```jbuilder
json.payload do
  json.array! @rules do |rule|
    json.partial! 'api/v1/models/captain/lifecycle_rule', resource: rule
  end
end

json.meta do
  json.total_count @rules.count
end
```

Criar `enterprise/app/views/api/v1/accounts/captain/lifecycle_rules/show.json.jbuilder`:

```jbuilder
json.partial! 'api/v1/models/captain/lifecycle_rule', resource: @rule
```

Criar `enterprise/app/views/api/v1/accounts/captain/lifecycle_rules/create.json.jbuilder`:

```jbuilder
json.partial! 'api/v1/models/captain/lifecycle_rule', resource: @rule
```

Criar `enterprise/app/views/api/v1/accounts/captain/lifecycle_rules/update.json.jbuilder`:

```jbuilder
json.partial! 'api/v1/models/captain/lifecycle_rule', resource: @rule
```

- [ ] **Step 7: Rodar e passar**

```bash
bundle exec rspec spec/enterprise/controllers/api/v1/accounts/captain/lifecycle_rules_controller_spec.rb
```
Esperado: PASS (6 examples).

- [ ] **Step 8: Commit**

```bash
git add enterprise/app/controllers/api/v1/accounts/captain/lifecycle_rules_controller.rb \
        enterprise/app/views/api/v1/models/captain/_lifecycle_rule.json.jbuilder \
        enterprise/app/views/api/v1/accounts/captain/lifecycle_rules \
        spec/enterprise/controllers/api/v1/accounts/captain/lifecycle_rules_controller_spec.rb \
        spec/factories/captain/lifecycle/rule.rb
git commit -m "feat(lifecycle): REST endpoint for lifecycle rules CRUD"
```

---

## Task 5: LifecycleConfigsController

**Files:**
- Create: `enterprise/app/controllers/api/v1/accounts/captain/lifecycle_configs_controller.rb`
- Create: `enterprise/app/views/api/v1/models/captain/_lifecycle_config.json.jbuilder`
- Create: `enterprise/app/views/api/v1/accounts/captain/lifecycle_configs/show.json.jbuilder`
- Create: `enterprise/app/views/api/v1/accounts/captain/lifecycle_configs/update.json.jbuilder`
- Create: `spec/enterprise/controllers/api/v1/accounts/captain/lifecycle_configs_controller_spec.rb`

- [ ] **Step 1: Spec falhando**

Criar `spec/enterprise/controllers/api/v1/accounts/captain/lifecycle_configs_controller_spec.rb`:

```ruby
require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::Captain::LifecycleConfigs', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }

  def json_response
    JSON.parse(response.body, symbolize_names: true)
  end

  describe 'GET /api/v1/accounts/:account_id/captain/lifecycle_config' do
    it 'creates a default config on first access' do
      get "/api/v1/accounts/#{account.id}/captain/lifecycle_config",
          headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
      expect(json_response[:quiet_hours_enabled]).to eq(false)
      expect(json_response[:min_interval_minutes]).to eq(30)
      expect(json_response[:max_per_reservation]).to eq(5)
    end
  end

  describe 'PATCH /api/v1/accounts/:account_id/captain/lifecycle_config' do
    it 'blocks agents' do
      patch "/api/v1/accounts/#{account.id}/captain/lifecycle_config",
            params: { config: { quiet_hours_enabled: true } },
            headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    it 'updates for admin' do
      patch "/api/v1/accounts/#{account.id}/captain/lifecycle_config",
            params: { config: { quiet_hours_enabled: true, quiet_hours_from: '22:00', min_interval_minutes: 60 } },
            headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
      expect(json_response[:quiet_hours_enabled]).to eq(true)
      expect(json_response[:min_interval_minutes]).to eq(60)
    end
  end
end
```

- [ ] **Step 2: Rodar e falhar**

```bash
bundle exec rspec spec/enterprise/controllers/api/v1/accounts/captain/lifecycle_configs_controller_spec.rb
```
Esperado: FAIL.

- [ ] **Step 3: Controller**

Criar `enterprise/app/controllers/api/v1/accounts/captain/lifecycle_configs_controller.rb`:

```ruby
class Api::V1::Accounts::Captain::LifecycleConfigsController < Api::V1::Accounts::BaseController
  before_action :current_account
  before_action :set_config
  before_action -> { check_authorization(@config) }

  def show; end

  def update
    @config.update!(config_params)
    render 'api/v1/accounts/captain/lifecycle_configs/show'
  end

  private

  def set_config
    @config = Captain::Lifecycle::Config.for_account(Current.account)
  end

  def config_params
    params.require(:config).permit(
      :quiet_hours_enabled, :quiet_hours_from, :quiet_hours_to,
      :min_interval_minutes, :pause_on_customer_reply,
      :pause_on_customer_reply_within_minutes, :opt_out_label_id
    )
  end
end
```

- [ ] **Step 4: Jbuilder partial**

Criar `enterprise/app/views/api/v1/models/captain/_lifecycle_config.json.jbuilder`:

```jbuilder
json.id resource.id
json.account_id resource.account_id
json.quiet_hours_enabled resource.quiet_hours_enabled
json.quiet_hours_from resource.quiet_hours_from&.strftime('%H:%M')
json.quiet_hours_to resource.quiet_hours_to&.strftime('%H:%M')
json.min_interval_minutes resource.min_interval_minutes
json.pause_on_customer_reply resource.pause_on_customer_reply
json.pause_on_customer_reply_within_minutes resource.pause_on_customer_reply_within_minutes
json.opt_out_label_id resource.opt_out_label_id
json.max_per_reservation 5
```

- [ ] **Step 5: Templates**

Criar `enterprise/app/views/api/v1/accounts/captain/lifecycle_configs/show.json.jbuilder`:

```jbuilder
json.partial! 'api/v1/models/captain/lifecycle_config', resource: @config
```

Criar `enterprise/app/views/api/v1/accounts/captain/lifecycle_configs/update.json.jbuilder`:

```jbuilder
json.partial! 'api/v1/models/captain/lifecycle_config', resource: @config
```

- [ ] **Step 6: Rodar e passar**

```bash
bundle exec rspec spec/enterprise/controllers/api/v1/accounts/captain/lifecycle_configs_controller_spec.rb
```
Esperado: PASS (3 examples).

- [ ] **Step 7: Commit**

```bash
git add enterprise/app/controllers/api/v1/accounts/captain/lifecycle_configs_controller.rb \
        enterprise/app/views/api/v1/models/captain/_lifecycle_config.json.jbuilder \
        enterprise/app/views/api/v1/accounts/captain/lifecycle_configs \
        spec/enterprise/controllers/api/v1/accounts/captain/lifecycle_configs_controller_spec.rb
git commit -m "feat(lifecycle): REST endpoint for lifecycle config singleton"
```

---

## Task 6: LifecycleDeliveriesController

**Files:**
- Create: `enterprise/app/controllers/api/v1/accounts/captain/lifecycle_deliveries_controller.rb`
- Create: `enterprise/app/views/api/v1/models/captain/_lifecycle_delivery.json.jbuilder`
- Create: `enterprise/app/views/api/v1/accounts/captain/lifecycle_deliveries/index.json.jbuilder`
- Create: `enterprise/app/views/api/v1/accounts/captain/lifecycle_deliveries/show.json.jbuilder`
- Create: `spec/enterprise/controllers/api/v1/accounts/captain/lifecycle_deliveries_controller_spec.rb`
- Create: `spec/factories/captain/lifecycle/delivery.rb`

- [ ] **Step 1: Factory**

Criar `spec/factories/captain/lifecycle/delivery.rb`:

```ruby
FactoryBot.define do
  factory :captain_lifecycle_delivery, class: 'Captain::Lifecycle::Delivery' do
    account
    captain_reservation
    fire_at { 10.minutes.from_now }
    status { 'scheduled' }
    origin { 'scheduled_lifecycle' }
  end
end
```

- [ ] **Step 2: Spec falhando**

Criar `spec/enterprise/controllers/api/v1/accounts/captain/lifecycle_deliveries_controller_spec.rb`:

```ruby
require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::Captain::LifecycleDeliveries', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:unit) { create(:captain_unit, account: account) }
  let(:reservation) { create(:captain_reservation, account: account, unit: unit) }

  def json_response
    JSON.parse(response.body, symbolize_names: true)
  end

  describe 'GET /api/v1/accounts/:account_id/captain/lifecycle_deliveries' do
    before do
      allow(Captain::Lifecycle::Scheduler).to receive(:schedule_for)
    end

    it 'returns deliveries of the account, paginated' do
      create_list(:captain_lifecycle_delivery, 3, account: account, captain_reservation: reservation)
      get "/api/v1/accounts/#{account.id}/captain/lifecycle_deliveries",
          headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(json_response[:payload].length).to eq(3)
      expect(json_response[:meta][:total_count]).to eq(3)
    end

    it 'filters by status' do
      create(:captain_lifecycle_delivery, account: account, captain_reservation: reservation, status: 'sent', sent_at: Time.current)
      create(:captain_lifecycle_delivery, account: account, captain_reservation: reservation, status: 'skipped', skip_reason: 'quiet_hours')

      get "/api/v1/accounts/#{account.id}/captain/lifecycle_deliveries?status=skipped",
          headers: admin.create_new_auth_token, as: :json

      expect(json_response[:payload].length).to eq(1)
      expect(json_response[:payload].first[:status]).to eq('skipped')
    end
  end

  describe 'GET /api/v1/accounts/:account_id/captain/lifecycle_deliveries/:id' do
    before { allow(Captain::Lifecycle::Scheduler).to receive(:schedule_for) }

    it 'returns the rendered_body' do
      delivery = create(:captain_lifecycle_delivery, account: account, captain_reservation: reservation,
                                                    rendered_body: 'Oi João!')
      get "/api/v1/accounts/#{account.id}/captain/lifecycle_deliveries/#{delivery.id}",
          headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(json_response[:rendered_body]).to eq('Oi João!')
    end
  end
end
```

- [ ] **Step 3: Rodar e falhar**

```bash
bundle exec rspec spec/enterprise/controllers/api/v1/accounts/captain/lifecycle_deliveries_controller_spec.rb
```

- [ ] **Step 4: Controller**

Criar `enterprise/app/controllers/api/v1/accounts/captain/lifecycle_deliveries_controller.rb`:

```ruby
class Api::V1::Accounts::Captain::LifecycleDeliveriesController < Api::V1::Accounts::BaseController
  RESULTS_PER_PAGE = 25
  MAX_RESULTS_PER_PAGE = 100

  before_action :current_account
  before_action -> { check_authorization(Captain::Lifecycle::Delivery) }
  before_action :set_page, only: [:index]
  before_action :set_delivery, only: [:show]

  def index
    scope = Current.account.captain_lifecycle_deliveries
                  .includes(:lifecycle_rule, captain_reservation: :contact)
                  .order(created_at: :desc)
    scope = scope.where(status: params[:status]) if params[:status].present?
    scope = scope.where(lifecycle_rule_id: params[:rule_id]) if params[:rule_id].present?
    scope = scope.where(captain_reservation_id: params[:reservation_id]) if params[:reservation_id].present?
    scope = scope.where('fire_at >= ?', params[:from]) if params[:from].present?
    scope = scope.where('fire_at <= ?', params[:to]) if params[:to].present?

    @total_count = scope.count
    @deliveries = scope.page(@page).per(@per_page)
  end

  def show; end

  private

  def set_page
    @page = (params[:page] || 1).to_i
    @per_page = [(params[:per_page] || RESULTS_PER_PAGE).to_i, MAX_RESULTS_PER_PAGE].min
  end

  def set_delivery
    @delivery = Current.account.captain_lifecycle_deliveries.find(params[:id])
  end
end
```

- [ ] **Step 5: Jbuilder partial**

Criar `enterprise/app/views/api/v1/models/captain/_lifecycle_delivery.json.jbuilder`:

```jbuilder
json.id resource.id
json.account_id resource.account_id
json.lifecycle_rule_id resource.lifecycle_rule_id
json.lifecycle_rule_name resource.lifecycle_rule&.name
json.captain_reservation_id resource.captain_reservation_id
json.conversation_id resource.conversation_id
json.inbox_id resource.inbox_id
json.fire_at resource.fire_at&.iso8601
json.sent_at resource.sent_at&.iso8601
json.status resource.status
json.skip_reason resource.skip_reason
json.failure_reason resource.failure_reason
json.rendered_body resource.rendered_body
json.origin resource.origin

if resource.captain_reservation
  json.reservation do
    json.id resource.captain_reservation.id
    json.suite_identifier resource.captain_reservation.suite_identifier
    contact = resource.captain_reservation.contact
    json.customer_name contact&.name
    json.customer_phone contact&.phone_number
  end
end
```

- [ ] **Step 6: Templates**

Criar `enterprise/app/views/api/v1/accounts/captain/lifecycle_deliveries/index.json.jbuilder`:

```jbuilder
json.payload do
  json.array! @deliveries do |delivery|
    json.partial! 'api/v1/models/captain/lifecycle_delivery', resource: delivery
  end
end

json.meta do
  json.total_count @total_count
  json.page @page
  json.per_page @per_page
end
```

Criar `enterprise/app/views/api/v1/accounts/captain/lifecycle_deliveries/show.json.jbuilder`:

```jbuilder
json.partial! 'api/v1/models/captain/lifecycle_delivery', resource: @delivery
```

- [ ] **Step 7: Rodar e passar**

```bash
bundle exec rspec spec/enterprise/controllers/api/v1/accounts/captain/lifecycle_deliveries_controller_spec.rb
```
Esperado: PASS (3 examples).

- [ ] **Step 8: Commit**

```bash
git add enterprise/app/controllers/api/v1/accounts/captain/lifecycle_deliveries_controller.rb \
        enterprise/app/views/api/v1/models/captain/_lifecycle_delivery.json.jbuilder \
        enterprise/app/views/api/v1/accounts/captain/lifecycle_deliveries \
        spec/enterprise/controllers/api/v1/accounts/captain/lifecycle_deliveries_controller_spec.rb \
        spec/factories/captain/lifecycle/delivery.rb
git commit -m "feat(lifecycle): REST endpoint for lifecycle deliveries audit log"
```

---

## Task 7: Estender UnitsController com `update_concierge`

**Files:**
- Modify: `enterprise/app/controllers/api/v1/accounts/captain/units_controller.rb`
- Modify: `enterprise/app/views/api/v1/models/captain/_unit.json.jbuilder` (adicionar campos concierge, se ainda não existirem)
- Create: `enterprise/app/views/api/v1/accounts/captain/units/concierge.json.jbuilder`
- Create/Modify: `spec/enterprise/controllers/api/v1/accounts/captain/units_controller_spec.rb` (adicionar contexto `update_concierge`)

- [ ] **Step 1: Ler controller atual**

Run: `cat enterprise/app/controllers/api/v1/accounts/captain/units_controller.rb` pra saber o formato do arquivo antes de editar.

- [ ] **Step 2: Spec falhando**

Adicionar ao final do describe principal em `spec/enterprise/controllers/api/v1/accounts/captain/units_controller_spec.rb` (criar o arquivo se não existir, seguindo o padrão do rules spec):

```ruby
  describe 'PATCH /api/v1/accounts/:account_id/captain/units/:id/concierge' do
    let(:unit) { create(:captain_unit, account: account) }
    let(:inbox) { create(:inbox, account: account) }

    it 'blocks agents' do
      patch "/api/v1/accounts/#{account.id}/captain/units/#{unit.id}/concierge",
            params: { unit: { concierge_inbox_id: inbox.id } },
            headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    it 'updates concierge fields for admin' do
      patch "/api/v1/accounts/#{account.id}/captain/units/#{unit.id}/concierge",
            params: {
              unit: {
                concierge_inbox_id: inbox.id,
                concierge_config: {
                  persona_name: 'Sofia',
                  knowledge: '# Hotel\n',
                  variables: { wifi_password: 'abc123' }
                }
              }
            },
            headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      unit.reload
      expect(unit.concierge_inbox_id).to eq(inbox.id)
      expect(unit.concierge_config['persona_name']).to eq('Sofia')
      expect(unit.concierge_config.dig('variables', 'wifi_password')).to eq('abc123')
    end
  end
```

- [ ] **Step 3: Rodar e falhar**

```bash
bundle exec rspec spec/enterprise/controllers/api/v1/accounts/captain/units_controller_spec.rb
```

- [ ] **Step 4: Implementar action no controller**

Adicionar ao `enterprise/app/controllers/api/v1/accounts/captain/units_controller.rb`:

```ruby
  def update_concierge
    @unit.update!(concierge_params)
    render 'api/v1/accounts/captain/units/concierge'
  end

  private

  def concierge_params
    params.require(:unit).permit(
      :concierge_inbox_id,
      concierge_config: [:persona_name, :knowledge, { variables: {} }]
    )
  end
```

Certifique-se que `before_action :set_unit, only: [:show, :update, :destroy, :update_concierge]` está na lista, e que a authorization do update cobre `update_concierge` (provavelmente `check_authorization(Captain::Unit)` já cobre porque checka `update?`).

- [ ] **Step 5: Jbuilder da action concierge**

Criar `enterprise/app/views/api/v1/accounts/captain/units/concierge.json.jbuilder`:

```jbuilder
json.id @unit.id
json.name @unit.name
json.concierge_inbox_id @unit.concierge_inbox_id
json.concierge_config @unit.concierge_config || {}
```

- [ ] **Step 6: Atualizar partial de unit**

Em `enterprise/app/views/api/v1/models/captain/_unit.json.jbuilder`, garantir que existem:

```jbuilder
json.concierge_inbox_id resource.concierge_inbox_id
json.concierge_config resource.concierge_config || {}
```

(se os campos não existirem no partial, adicionar).

- [ ] **Step 7: Rodar e passar**

```bash
bundle exec rspec spec/enterprise/controllers/api/v1/accounts/captain/units_controller_spec.rb
```

- [ ] **Step 8: Commit**

```bash
git add enterprise/app/controllers/api/v1/accounts/captain/units_controller.rb \
        enterprise/app/views/api/v1/accounts/captain/units \
        enterprise/app/views/api/v1/models/captain/_unit.json.jbuilder \
        spec/enterprise/controllers/api/v1/accounts/captain/units_controller_spec.rb
git commit -m "feat(lifecycle): expose concierge config update on UnitsController"
```

---

## Task 8: i18n scaffolding (pt_BR + en)

**Files:**
- Modify: `app/javascript/dashboard/i18n/locale/pt_BR/captain.json`
- Modify: `app/javascript/dashboard/i18n/locale/en/captain.json`
- Modify: `app/javascript/dashboard/i18n/locale/pt_BR/settings.json` (chave `SIDEBAR.CAPTAIN_LIFECYCLE`)
- Modify: `app/javascript/dashboard/i18n/locale/en/settings.json`

- [ ] **Step 1: Adicionar bloco `CAPTAIN_LIFECYCLE` em pt_BR/captain.json**

Adicionar antes do último `}` do JSON (fechando o objeto raiz):

```json
  "CAPTAIN_LIFECYCLE": {
    "HEADER": "Jornada do Cliente",
    "SUBTITLE": "Automação de mensagens WhatsApp no ciclo de vida da reserva",
    "TABS": {
      "RULES": "Regras",
      "SETTINGS": "Configurações",
      "HISTORY": "Histórico"
    },
    "RULES": {
      "EMPTY": "Nenhuma regra configurada ainda.",
      "CREATE": "Nova regra",
      "TEMPLATES_TITLE": "Templates prontos",
      "COLUMNS": {
        "NAME": "Nome",
        "EVENT": "Evento",
        "OFFSET": "Offset",
        "FILTER": "Filtro",
        "STATUS": "Status",
        "ACTIONS": "Ações"
      },
      "STATUS": {
        "ENABLED": "Ativo",
        "DISABLED": "Desativado"
      },
      "ACTIONS": {
        "EDIT": "Editar",
        "DUPLICATE": "Duplicar",
        "TOGGLE": "Ativar/Desativar",
        "DELETE": "Excluir"
      },
      "DELETE_CONFIRM": "Tem certeza que deseja excluir esta regra?",
      "TOAST": {
        "CREATED": "Regra criada com sucesso.",
        "UPDATED": "Regra atualizada.",
        "DELETED": "Regra excluída."
      },
      "WIZARD": {
        "TITLE_CREATE": "Nova regra",
        "TITLE_EDIT": "Editar regra",
        "STEP_WHEN": "Quando?",
        "STEP_WHO": "Pra quem?",
        "STEP_WHAT": "O quê?",
        "STEP_REVIEW": "Revisão",
        "NEXT": "Próximo",
        "BACK": "Voltar",
        "SAVE": "Salvar",
        "FIELDS": {
          "NAME": "Nome da regra",
          "DESCRIPTION": "Descrição",
          "EVENT": "Evento gatilho",
          "OFFSET_VALUE": "Valor",
          "OFFSET_UNIT": "Unidade",
          "OFFSET_DIRECTION": "Direção",
          "UNITS": "Unidades",
          "CATEGORIAS": "Categorias de suíte",
          "PERMANENCIAS": "Tipos de permanência",
          "MESSAGE_TYPE": "Tipo de mensagem",
          "MESSAGE_BODY": "Texto da mensagem",
          "PRIORITY": "Prioridade",
          "ENABLED": "Regra ativa"
        },
        "OFFSET_UNITS": {
          "MINUTES": "Minutos",
          "HOURS": "Horas",
          "DAYS": "Dias"
        },
        "OFFSET_DIRECTIONS": {
          "BEFORE": "Antes",
          "AFTER": "Depois"
        },
        "EVENTS": {
          "RESERVATION_CONFIRMED": "Reserva confirmada (Pix pago)",
          "CHECKIN_SCHEDULED_AT": "Horário de check-in",
          "CHECKOUT_SCHEDULED_AT": "Horário de check-out",
          "RESERVATION_CANCELLED": "Reserva cancelada",
          "RESERVATION_NO_SHOW": "No-show"
        },
        "MESSAGE_TYPES": {
          "TEXT": "Texto simples",
          "BUTTONS": "Texto com botões",
          "LIST": "Menu de lista",
          "URL_BUTTON": "Botão de link"
        }
      }
    },
    "SETTINGS": {
      "GUARDS_TITLE": "Guards anti-spam",
      "QUIET_HOURS_ENABLED": "Ativar quiet hours",
      "QUIET_HOURS_FROM": "De",
      "QUIET_HOURS_TO": "Até",
      "MIN_INTERVAL": "Intervalo mínimo entre mensagens (min)",
      "MIN_INTERVAL_HELP": "0 desativa",
      "PAUSE_ON_REPLY": "Pausar se o cliente respondeu",
      "PAUSE_ON_REPLY_WINDOW": "Janela (min)",
      "OPT_OUT_LABEL": "Label de opt-out",
      "MAX_PER_RESERVATION_INFO": "Máximo de 5 mensagens por reserva (não configurável)",
      "CONCIERGE_TITLE": "Concierge (Sofia) por Unidade",
      "CONCIERGE_INBOX": "Inbox WhatsApp",
      "CONCIERGE_PERSONA": "Nome da persona",
      "CONCIERGE_KNOWLEDGE": "Base de conhecimento (markdown)",
      "CONCIERGE_VARIABLES": "Variáveis da unidade",
      "CONCIERGE_VARIABLE_KEY": "Chave",
      "CONCIERGE_VARIABLE_VALUE": "Valor",
      "CONCIERGE_ADD_VARIABLE": "Adicionar variável",
      "SAVE": "Salvar alterações",
      "TOAST": {
        "SAVED": "Configurações salvas.",
        "CONCIERGE_SAVED": "Concierge da unidade atualizado."
      }
    },
    "HISTORY": {
      "EMPTY": "Nenhuma entrega registrada.",
      "COLUMNS": {
        "RULE": "Regra",
        "CUSTOMER": "Cliente",
        "RESERVATION": "Reserva",
        "STATUS": "Status",
        "FIRE_AT": "Disparado em",
        "REASON": "Motivo",
        "ACTIONS": ""
      },
      "STATUS": {
        "SCHEDULED": "Agendada",
        "SENT": "Enviada",
        "SKIPPED": "Pulada",
        "FAILED": "Falhou",
        "CANCELLED": "Cancelada"
      },
      "FILTERS": {
        "STATUS": "Status",
        "RULE": "Regra",
        "FROM": "De",
        "TO": "Até",
        "ALL": "Todas"
      },
      "PREVIEW": "Preview",
      "MODAL": {
        "TITLE": "Preview da mensagem",
        "CLOSE": "Fechar"
      }
    }
  }
```

- [ ] **Step 2: Duplicar em en/captain.json traduzido pra inglês**

Mesma estrutura com valores em inglês ("Customer Journey", "Rules", "Settings", "History", etc). Preservar as **keys** exatas.

- [ ] **Step 3: Adicionar chave de sidebar**

Em `app/javascript/dashboard/i18n/locale/pt_BR/settings.json`, procurar `"CAPTAIN_RESERVATIONS"` dentro de `SIDEBAR` e adicionar logo após:

```json
      "CAPTAIN_LIFECYCLE": "Jornada do Cliente",
```

Mesma coisa em `en/settings.json` com valor `"Customer Journey"`.

- [ ] **Step 4: Sync i18n**

```bash
pnpm run sync:i18n
```
(Não deve acusar erro. Se acusar key faltando em outro locale, ignorar se não for en/pt_BR — o projeto só mantém esses dois em dia.)

- [ ] **Step 5: Commit**

```bash
git add app/javascript/dashboard/i18n/locale/pt_BR/captain.json \
        app/javascript/dashboard/i18n/locale/en/captain.json \
        app/javascript/dashboard/i18n/locale/pt_BR/settings.json \
        app/javascript/dashboard/i18n/locale/en/settings.json
git commit -m "feat(lifecycle): i18n keys for Jornada do Cliente UI"
```

---

## Task 9: API clients (Vue)

**Files:**
- Create: `app/javascript/dashboard/api/captain/lifecycleRules.js`
- Create: `app/javascript/dashboard/api/captain/lifecycleConfig.js`
- Create: `app/javascript/dashboard/api/captain/lifecycleDeliveries.js`

- [ ] **Step 1: Criar `lifecycleRules.js`**

```javascript
/* global axios */
import ApiClient from '../ApiClient';

class CaptainLifecycleRules extends ApiClient {
  constructor() {
    super('captain/lifecycle_rules', { accountScoped: true });
  }

  get(params = {}) {
    return axios.get(this.url, { params });
  }

  show(id) {
    return axios.get(`${this.url}/${id}`);
  }

  create(data) {
    return axios.post(this.url, { rule: data });
  }

  update(id, data) {
    return axios.patch(`${this.url}/${id}`, { rule: data });
  }

  delete(id) {
    return axios.delete(`${this.url}/${id}`);
  }
}

export default new CaptainLifecycleRules();
```

- [ ] **Step 2: Criar `lifecycleConfig.js`**

```javascript
/* global axios */
import ApiClient from '../ApiClient';

class CaptainLifecycleConfig extends ApiClient {
  constructor() {
    super('captain/lifecycle_config', { accountScoped: true });
  }

  show() {
    return axios.get(this.url);
  }

  update(data) {
    return axios.patch(this.url, { config: data });
  }

  updateConcierge(unitId, payload) {
    const accountId = this.options.accountScoped
      ? `accounts/${window.authAPI.accountId}`
      : '';
    return axios.patch(
      `/api/v1/${accountId}/captain/units/${unitId}/concierge`,
      { unit: payload }
    );
  }
}

export default new CaptainLifecycleConfig();
```

**Nota:** verificar como `ApiClient` expõe `accountId` — se houver método `urlFor`, usar ele. Pode precisar de `import AuthAPI` ou usar `this.baseUrl()`. Se não ficar claro, fazer chamada diretamente via `axios.patch(\`/api/v1/accounts/${window.bus.$store.getters.getCurrentAccountId}/...\`)` ou simplesmente colocar o método `updateConcierge` no client `CaptainUnitsAPI` existente.

- [ ] **Step 3: Criar `lifecycleDeliveries.js`**

```javascript
/* global axios */
import ApiClient from '../ApiClient';

class CaptainLifecycleDeliveries extends ApiClient {
  constructor() {
    super('captain/lifecycle_deliveries', { accountScoped: true });
  }

  get(params = {}) {
    return axios.get(this.url, { params });
  }

  show(id) {
    return axios.get(`${this.url}/${id}`);
  }
}

export default new CaptainLifecycleDeliveries();
```

- [ ] **Step 4: Rodar eslint**

```bash
pnpm run eslint app/javascript/dashboard/api/captain/lifecycleRules.js app/javascript/dashboard/api/captain/lifecycleConfig.js app/javascript/dashboard/api/captain/lifecycleDeliveries.js
```

- [ ] **Step 5: Commit**

```bash
git add app/javascript/dashboard/api/captain/lifecycleRules.js \
        app/javascript/dashboard/api/captain/lifecycleConfig.js \
        app/javascript/dashboard/api/captain/lifecycleDeliveries.js
git commit -m "feat(lifecycle): API clients for rules/config/deliveries"
```

---

## Task 10: Pinia stores + registro

**Files:**
- Create: `app/javascript/dashboard/store/captain/lifecycleRules.js`
- Create: `app/javascript/dashboard/store/captain/lifecycleConfig.js`
- Create: `app/javascript/dashboard/store/captain/lifecycleDeliveries.js`
- Modify: `app/javascript/dashboard/store/index.js`

- [ ] **Step 1: Store `lifecycleRules.js` (factory completa)**

```javascript
import CaptainLifecycleRulesAPI from 'dashboard/api/captain/lifecycleRules';
import { createStore } from '../storeFactory';
import { throwErrorMessage } from 'dashboard/store/utils/api';

export default createStore({
  name: 'CaptainLifecycleRule',
  API: CaptainLifecycleRulesAPI,
  actions: mutations => ({
    create: async ({ commit }, data) => {
      commit(mutations.SET_UI_FLAG, { creatingItem: true });
      try {
        const response = await CaptainLifecycleRulesAPI.create(data);
        commit(mutations.ADD, response.data);
        return response.data;
      } catch (error) {
        return throwErrorMessage(error);
      } finally {
        commit(mutations.SET_UI_FLAG, { creatingItem: false });
      }
    },
    update: async ({ commit }, { id, ...data }) => {
      commit(mutations.SET_UI_FLAG, { updatingItem: true });
      try {
        const response = await CaptainLifecycleRulesAPI.update(id, data);
        commit(mutations.EDIT, response.data);
        return response.data;
      } catch (error) {
        return throwErrorMessage(error);
      } finally {
        commit(mutations.SET_UI_FLAG, { updatingItem: false });
      }
    },
    delete: async ({ commit }, id) => {
      commit(mutations.SET_UI_FLAG, { deletingItem: true });
      try {
        await CaptainLifecycleRulesAPI.delete(id);
        commit(mutations.DELETE, id);
        return id;
      } catch (error) {
        return throwErrorMessage(error);
      } finally {
        commit(mutations.SET_UI_FLAG, { deletingItem: false });
      }
    },
  }),
});
```

- [ ] **Step 2: Store `lifecycleConfig.js` (singleton)**

O factory assume lista de registros. Pro config (singleton), escrevemos um módulo Vuex manual:

```javascript
import CaptainLifecycleConfigAPI from 'dashboard/api/captain/lifecycleConfig';
import { throwErrorMessage } from 'dashboard/store/utils/api';

export const types = {
  SET_CONFIG: 'SET_LIFECYCLE_CONFIG',
  SET_UI_FLAG: 'SET_LIFECYCLE_CONFIG_UI_FLAG',
};

const state = {
  config: {},
  uiFlags: {
    fetching: false,
    updating: false,
  },
};

const getters = {
  getConfig: $state => $state.config,
  getUIFlags: $state => $state.uiFlags,
};

const actions = {
  fetch: async ({ commit }) => {
    commit(types.SET_UI_FLAG, { fetching: true });
    try {
      const response = await CaptainLifecycleConfigAPI.show();
      commit(types.SET_CONFIG, response.data);
    } catch (error) {
      throwErrorMessage(error);
    } finally {
      commit(types.SET_UI_FLAG, { fetching: false });
    }
  },
  update: async ({ commit }, data) => {
    commit(types.SET_UI_FLAG, { updating: true });
    try {
      const response = await CaptainLifecycleConfigAPI.update(data);
      commit(types.SET_CONFIG, response.data);
      return response.data;
    } catch (error) {
      return throwErrorMessage(error);
    } finally {
      commit(types.SET_UI_FLAG, { updating: false });
    }
  },
};

const mutations = {
  [types.SET_CONFIG]($state, config) {
    $state.config = config;
  },
  [types.SET_UI_FLAG]($state, flags) {
    $state.uiFlags = { ...$state.uiFlags, ...flags };
  },
};

export default {
  namespaced: true,
  state,
  getters,
  actions,
  mutations,
};
```

- [ ] **Step 3: Store `lifecycleDeliveries.js`**

```javascript
import CaptainLifecycleDeliveriesAPI from 'dashboard/api/captain/lifecycleDeliveries';
import { createStore } from '../storeFactory';

export default createStore({
  name: 'CaptainLifecycleDelivery',
  API: CaptainLifecycleDeliveriesAPI,
});
```

- [ ] **Step 4: Registrar no `store/index.js`**

Em `app/javascript/dashboard/store/index.js`, localizar a linha `import captainReservations from './captain/reservations';` e adicionar abaixo:

```javascript
import captainLifecycleRules from './captain/lifecycleRules';
import captainLifecycleConfig from './captain/lifecycleConfig';
import captainLifecycleDeliveries from './captain/lifecycleDeliveries';
```

E no objeto `modules:` (onde está `captainReservations,`) adicionar:

```javascript
    captainLifecycleRules,
    captainLifecycleConfig,
    captainLifecycleDeliveries,
```

- [ ] **Step 5: Rodar eslint**

```bash
pnpm run eslint app/javascript/dashboard/store/captain/lifecycleRules.js \
                app/javascript/dashboard/store/captain/lifecycleConfig.js \
                app/javascript/dashboard/store/captain/lifecycleDeliveries.js \
                app/javascript/dashboard/store/index.js
```

- [ ] **Step 6: Commit**

```bash
git add app/javascript/dashboard/store/captain/lifecycleRules.js \
        app/javascript/dashboard/store/captain/lifecycleConfig.js \
        app/javascript/dashboard/store/captain/lifecycleDeliveries.js \
        app/javascript/dashboard/store/index.js
git commit -m "feat(lifecycle): Pinia/Vuex stores for rules/config/deliveries"
```

---

## Task 11: Rotas frontend + parent view com TabBar

**Files:**
- Create: `app/javascript/dashboard/routes/dashboard/captain/lifecycle/Index.vue`
- Create: `app/javascript/dashboard/routes/dashboard/captain/lifecycle/Rules.vue` (stub)
- Create: `app/javascript/dashboard/routes/dashboard/captain/lifecycle/Settings.vue` (stub)
- Create: `app/javascript/dashboard/routes/dashboard/captain/lifecycle/History.vue` (stub)
- Create: `app/javascript/dashboard/routes/dashboard/captain/lifecycle/constants.js`
- Modify: `app/javascript/dashboard/routes/dashboard/captain/captain.routes.js`

- [ ] **Step 1: constants.js**

```javascript
export const EVENTS = [
  { value: 'reservation.confirmed', labelKey: 'CAPTAIN_LIFECYCLE.RULES.WIZARD.EVENTS.RESERVATION_CONFIRMED' },
  { value: 'checkin.scheduled_at', labelKey: 'CAPTAIN_LIFECYCLE.RULES.WIZARD.EVENTS.CHECKIN_SCHEDULED_AT' },
  { value: 'checkout.scheduled_at', labelKey: 'CAPTAIN_LIFECYCLE.RULES.WIZARD.EVENTS.CHECKOUT_SCHEDULED_AT' },
  { value: 'reservation.cancelled', labelKey: 'CAPTAIN_LIFECYCLE.RULES.WIZARD.EVENTS.RESERVATION_CANCELLED' },
  { value: 'reservation.no_show', labelKey: 'CAPTAIN_LIFECYCLE.RULES.WIZARD.EVENTS.RESERVATION_NO_SHOW' },
];

export const MESSAGE_TYPES = [
  { value: 'text', labelKey: 'CAPTAIN_LIFECYCLE.RULES.WIZARD.MESSAGE_TYPES.TEXT' },
  { value: 'buttons', labelKey: 'CAPTAIN_LIFECYCLE.RULES.WIZARD.MESSAGE_TYPES.BUTTONS' },
  { value: 'list', labelKey: 'CAPTAIN_LIFECYCLE.RULES.WIZARD.MESSAGE_TYPES.LIST' },
  { value: 'url_button', labelKey: 'CAPTAIN_LIFECYCLE.RULES.WIZARD.MESSAGE_TYPES.URL_BUTTON' },
];

export const OFFSET_UNITS = [
  { value: 'minutes', factor: 1 },
  { value: 'hours', factor: 60 },
  { value: 'days', factor: 1440 },
];

export const AVAILABLE_VARIABLES = [
  { key: 'customer.first_name', descKey: 'Primeiro nome do cliente' },
  { key: 'customer.name', descKey: 'Nome completo' },
  { key: 'customer.phone', descKey: 'Telefone' },
  { key: 'reservation.suite', descKey: 'Suíte' },
  { key: 'reservation.unit_name', descKey: 'Nome da unidade' },
  { key: 'reservation.check_in_at', descKey: 'Check-in' },
  { key: 'reservation.check_out_at', descKey: 'Check-out' },
  { key: 'reservation.amount', descKey: 'Valor' },
  { key: 'hotel.wifi_password', descKey: 'Senha do WiFi' },
  { key: 'hotel.menu_link', descKey: 'Link do cardápio' },
  { key: 'hotel.google_review_link', descKey: 'Link de review' },
  { key: 'hotel.address', descKey: 'Endereço' },
];

export const RULE_TEMPLATES = [
  {
    id: 'precheckin_reminder',
    name: 'Lembrete 10min antes do check-in',
    event: 'checkin.scheduled_at',
    offset_minutes: -10,
    message_type: 'text',
    message_body:
      'Oi {{ customer.first_name }}! Seu check-in é em 10 minutos na suíte {{ reservation.suite }}. Wifi: {{ hotel.wifi_password }}',
  },
  {
    id: 'welcome_instay',
    name: 'Boas-vindas após check-in',
    event: 'checkin.scheduled_at',
    offset_minutes: 15,
    message_type: 'text',
    message_body:
      'Seja bem-vindo(a), {{ customer.first_name }}! Qualquer coisa, só chamar. Cardápio: {{ hotel.menu_link }}',
  },
  {
    id: 'review_request',
    name: 'Pedido de review no Google',
    event: 'checkout.scheduled_at',
    offset_minutes: 120,
    message_type: 'url_button',
    message_body:
      '{{ customer.first_name }}, adoraríamos saber como foi sua estadia. Se puder, deixa um review pra gente: {{ hotel.google_review_link }}',
  },
];
```

- [ ] **Step 2: `Index.vue` (parent com TabBar)**

```vue
<script setup>
import { computed } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import PageLayout from 'dashboard/components-next/captain/PageLayout.vue';
import TabBar from 'dashboard/components-next/tabbar/TabBar.vue';

const { t } = useI18n();
const route = useRoute();
const router = useRouter();

const tabs = computed(() => [
  { name: 'captain_lifecycle_rules', label: t('CAPTAIN_LIFECYCLE.TABS.RULES') },
  { name: 'captain_lifecycle_settings', label: t('CAPTAIN_LIFECYCLE.TABS.SETTINGS') },
  { name: 'captain_lifecycle_history', label: t('CAPTAIN_LIFECYCLE.TABS.HISTORY') },
]);

const activeIndex = computed(() =>
  Math.max(0, tabs.value.findIndex(t2 => t2.name === route.name))
);

const handleTabChanged = tab => {
  router.push({ name: tab.name, params: route.params });
};
</script>

<template>
  <PageLayout
    :header-title="t('CAPTAIN_LIFECYCLE.HEADER')"
    :header-subtitle="t('CAPTAIN_LIFECYCLE.SUBTITLE')"
  >
    <div class="flex flex-col gap-4">
      <TabBar
        :tabs="tabs"
        :initial-active-tab="activeIndex"
        @tab-changed="handleTabChanged"
      />
      <router-view />
    </div>
  </PageLayout>
</template>
```

- [ ] **Step 3: Stubs dos 3 filhos**

Criar `Rules.vue`, `Settings.vue`, `History.vue` com o mesmo esqueleto mínimo:

```vue
<script setup>
import { useI18n } from 'vue-i18n';
const { t } = useI18n();
</script>

<template>
  <div class="p-6">
    <h2 class="text-lg font-semibold">{{ t('CAPTAIN_LIFECYCLE.TABS.RULES') }}</h2>
    <!-- TODO Task 14 -->
  </div>
</template>
```

(Ajustar o `t(...)` pra `SETTINGS` e `HISTORY` nos respectivos.)

- [ ] **Step 4: Registrar rotas**

Em `app/javascript/dashboard/routes/dashboard/captain/captain.routes.js`, adicionar imports no topo:

```javascript
import LifecycleIndex from './lifecycle/Index.vue';
import LifecycleRules from './lifecycle/Rules.vue';
import LifecycleSettings from './lifecycle/Settings.vue';
import LifecycleHistory from './lifecycle/History.vue';
```

E adicionar ao array `routes` (após a entrada de `captain_reservations_index`):

```javascript
  {
    path: frontendURL('accounts/:accountId/captain/lifecycle'),
    component: LifecycleIndex,
    meta,
    redirect: { name: 'captain_lifecycle_rules' },
    children: [
      {
        path: 'rules',
        component: LifecycleRules,
        name: 'captain_lifecycle_rules',
        meta,
      },
      {
        path: 'settings',
        component: LifecycleSettings,
        name: 'captain_lifecycle_settings',
        meta,
      },
      {
        path: 'history',
        component: LifecycleHistory,
        name: 'captain_lifecycle_history',
        meta,
      },
    ],
  },
```

- [ ] **Step 5: Subir dev e testar navegação**

```bash
pnpm run dev
```

Abrir `http://localhost:3000/app/accounts/<id>/captain/lifecycle` → deve redirecionar pra `/rules`, exibir TabBar com 3 abas e clicar em cada uma navega entre stubs. Verificar console sem erros.

- [ ] **Step 6: Commit**

```bash
git add app/javascript/dashboard/routes/dashboard/captain/lifecycle \
        app/javascript/dashboard/routes/dashboard/captain/captain.routes.js
git commit -m "feat(lifecycle): parent view with TabBar + 3 stub children routes"
```

---

## Task 12: Sidebar — entrada "Jornada do Cliente"

**Files:**
- Modify: `app/javascript/dashboard/components-next/sidebar/Sidebar.vue`

- [ ] **Step 1: Adicionar entrada no grupo Captain**

Localizar o bloco que contém `CAPTAIN_RESERVATIONS` (linha ~406). Adicionar **antes** dele:

```javascript
        {
          name: 'Lifecycle',
          label: t('SIDEBAR.CAPTAIN_LIFECYCLE'),
          activeOn: [
            'captain_lifecycle_rules',
            'captain_lifecycle_settings',
            'captain_lifecycle_history',
          ],
          to: accountScopedRoute('captain_lifecycle_rules'),
        },
```

- [ ] **Step 2: Recarregar dev e verificar sidebar**

Abrir o app, expandir menu Captain no sidebar — deve aparecer "Jornada do Cliente" e levar pra `/rules`.

- [ ] **Step 3: Commit**

```bash
git add app/javascript/dashboard/components-next/sidebar/Sidebar.vue
git commit -m "feat(lifecycle): sidebar entry for Jornada do Cliente"
```

---

## Task 13: Tab Histórico — tabela + modal preview

**Files:**
- Modify: `app/javascript/dashboard/routes/dashboard/captain/lifecycle/History.vue` (implementação completa)
- Create: `app/javascript/dashboard/routes/dashboard/captain/lifecycle/components/DeliveryPreviewModal.vue`

- [ ] **Step 1: DeliveryPreviewModal.vue**

```vue
<script setup>
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  delivery: { type: Object, default: null },
});
const emit = defineEmits(['close']);
const { t } = useI18n();
</script>

<template>
  <div
    v-if="delivery"
    class="fixed inset-0 z-50 flex items-center justify-center bg-black/40"
    @click.self="emit('close')"
  >
    <div class="bg-n-solid-1 rounded-xl p-6 w-[560px] max-h-[80vh] overflow-auto shadow-xl">
      <h3 class="text-lg font-semibold mb-4">
        {{ t('CAPTAIN_LIFECYCLE.HISTORY.MODAL.TITLE') }}
      </h3>
      <div class="space-y-3 text-sm">
        <div><strong>Regra:</strong> {{ delivery.lifecycle_rule_name || '—' }}</div>
        <div><strong>Status:</strong> {{ delivery.status }}</div>
        <div v-if="delivery.skip_reason"><strong>Motivo:</strong> {{ delivery.skip_reason }}</div>
        <div v-if="delivery.failure_reason"><strong>Erro:</strong> {{ delivery.failure_reason }}</div>
        <div><strong>Fire at:</strong> {{ delivery.fire_at }}</div>
        <div v-if="delivery.sent_at"><strong>Sent at:</strong> {{ delivery.sent_at }}</div>
        <div>
          <strong>Rendered:</strong>
          <pre class="mt-1 p-3 bg-n-alpha-2 rounded whitespace-pre-wrap">{{ delivery.rendered_body || '—' }}</pre>
        </div>
      </div>
      <div class="flex justify-end mt-6">
        <Button variant="outline" @click="emit('close')">
          {{ t('CAPTAIN_LIFECYCLE.HISTORY.MODAL.CLOSE') }}
        </Button>
      </div>
    </div>
  </div>
</template>
```

- [ ] **Step 2: History.vue implementação**

```vue
<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import DeliveryPreviewModal from './components/DeliveryPreviewModal.vue';

const store = useStore();
const { t } = useI18n();

const deliveries = useMapGetter('captainLifecycleDeliveries/getRecords');
const meta = useMapGetter('captainLifecycleDeliveries/getMeta');
const uiFlags = useMapGetter('captainLifecycleDeliveries/getUIFlags');

const status = ref('');
const page = ref(1);
const selectedDelivery = ref(null);

const STATUS_OPTIONS = [
  { value: '', key: 'ALL' },
  { value: 'scheduled', key: 'SCHEDULED' },
  { value: 'sent', key: 'SENT' },
  { value: 'skipped', key: 'SKIPPED' },
  { value: 'failed', key: 'FAILED' },
  { value: 'cancelled', key: 'CANCELLED' },
];

const fetchDeliveries = () => {
  store.dispatch('captainLifecycleDeliveries/get', {
    page: page.value,
    ...(status.value ? { status: status.value } : {}),
  });
};

onMounted(fetchDeliveries);
watch([status, page], fetchDeliveries);

const isLoading = computed(() => uiFlags.value.fetchingList);
const totalCount = computed(() => meta.value.total_count || 0);
</script>

<template>
  <div class="p-6">
    <div class="flex items-center gap-4 mb-4">
      <label class="flex items-center gap-2 text-sm">
        {{ t('CAPTAIN_LIFECYCLE.HISTORY.FILTERS.STATUS') }}:
        <select v-model="status" class="border rounded px-2 py-1">
          <option
            v-for="opt in STATUS_OPTIONS"
            :key="opt.value"
            :value="opt.value"
          >
            {{ opt.value ? t(`CAPTAIN_LIFECYCLE.HISTORY.STATUS.${opt.key}`) : t('CAPTAIN_LIFECYCLE.HISTORY.FILTERS.ALL') }}
          </option>
        </select>
      </label>
      <span class="text-sm text-n-slate-11">{{ totalCount }} total</span>
    </div>

    <div v-if="isLoading" class="flex justify-center py-8"><Spinner /></div>

    <div v-else-if="deliveries.length === 0" class="text-center py-8 text-n-slate-11">
      {{ t('CAPTAIN_LIFECYCLE.HISTORY.EMPTY') }}
    </div>

    <table v-else class="w-full text-sm">
      <thead class="text-left text-n-slate-11">
        <tr>
          <th class="py-2">{{ t('CAPTAIN_LIFECYCLE.HISTORY.COLUMNS.RULE') }}</th>
          <th>{{ t('CAPTAIN_LIFECYCLE.HISTORY.COLUMNS.CUSTOMER') }}</th>
          <th>{{ t('CAPTAIN_LIFECYCLE.HISTORY.COLUMNS.RESERVATION') }}</th>
          <th>{{ t('CAPTAIN_LIFECYCLE.HISTORY.COLUMNS.STATUS') }}</th>
          <th>{{ t('CAPTAIN_LIFECYCLE.HISTORY.COLUMNS.FIRE_AT') }}</th>
          <th>{{ t('CAPTAIN_LIFECYCLE.HISTORY.COLUMNS.REASON') }}</th>
          <th></th>
        </tr>
      </thead>
      <tbody>
        <tr v-for="d in deliveries" :key="d.id" class="border-t border-n-slate-4">
          <td class="py-2">{{ d.lifecycle_rule_name || '—' }}</td>
          <td>{{ d.reservation?.customer_name || '—' }}</td>
          <td>#{{ d.captain_reservation_id }}</td>
          <td>{{ t(`CAPTAIN_LIFECYCLE.HISTORY.STATUS.${d.status.toUpperCase()}`) }}</td>
          <td>{{ new Date(d.fire_at).toLocaleString('pt-BR') }}</td>
          <td>{{ d.skip_reason || d.failure_reason || '' }}</td>
          <td>
            <Button size="sm" variant="ghost" @click="selectedDelivery = d">
              {{ t('CAPTAIN_LIFECYCLE.HISTORY.PREVIEW') }}
            </Button>
          </td>
        </tr>
      </tbody>
    </table>

    <div class="flex justify-center gap-2 mt-4">
      <Button :disabled="page <= 1" @click="page -= 1">«</Button>
      <span class="text-sm">{{ page }}</span>
      <Button :disabled="deliveries.length < 25" @click="page += 1">»</Button>
    </div>

    <DeliveryPreviewModal
      :delivery="selectedDelivery"
      @close="selectedDelivery = null"
    />
  </div>
</template>
```

- [ ] **Step 3: Testar manualmente**

Ainda com `pnpm run dev` rodando, navegar até `/captain/lifecycle/history`. Sem dados deve mostrar empty state. Via console Rails (`bundle exec rails console`), criar uma `Captain::Lifecycle::Delivery` de teste. Recarregar e ver entrada; clicar em "Preview" abre modal com `rendered_body`.

- [ ] **Step 4: Eslint**

```bash
pnpm run eslint app/javascript/dashboard/routes/dashboard/captain/lifecycle/History.vue \
                app/javascript/dashboard/routes/dashboard/captain/lifecycle/components/DeliveryPreviewModal.vue
```

- [ ] **Step 5: Commit**

```bash
git add app/javascript/dashboard/routes/dashboard/captain/lifecycle/History.vue \
        app/javascript/dashboard/routes/dashboard/captain/lifecycle/components/DeliveryPreviewModal.vue
git commit -m "feat(lifecycle): history tab with paginated list and preview modal"
```

---

## Task 14: Tab Configurações — guards form + Sofia por unidade

**Files:**
- Modify: `app/javascript/dashboard/routes/dashboard/captain/lifecycle/Settings.vue`
- Create: `app/javascript/dashboard/routes/dashboard/captain/lifecycle/components/ConciergeUnitCard.vue`

- [ ] **Step 1: ConciergeUnitCard.vue**

```vue
<script setup>
import { ref, watch } from 'vue';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import Input from 'dashboard/components-next/input/Input.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import CaptainLifecycleConfigAPI from 'dashboard/api/captain/lifecycleConfig';

const props = defineProps({ unit: { type: Object, required: true } });
const { t } = useI18n();

const inboxes = useMapGetter('inboxes/getWhatsAppInboxes');

const expanded = ref(false);
const conciergeInboxId = ref(props.unit.concierge_inbox_id || null);
const personaName = ref(props.unit.concierge_config?.persona_name || 'Sofia');
const knowledge = ref(props.unit.concierge_config?.knowledge || '');
const variables = ref(
  Object.entries(props.unit.concierge_config?.variables || {}).map(([k, v]) => ({ k, v }))
);

const addVariable = () => variables.value.push({ k: '', v: '' });
const removeVariable = i => variables.value.splice(i, 1);

const save = async () => {
  try {
    const varsObj = Object.fromEntries(variables.value.filter(x => x.k).map(x => [x.k, x.v]));
    await CaptainLifecycleConfigAPI.updateConcierge(props.unit.id, {
      concierge_inbox_id: conciergeInboxId.value,
      concierge_config: {
        persona_name: personaName.value,
        knowledge: knowledge.value,
        variables: varsObj,
      },
    });
    useAlert(t('CAPTAIN_LIFECYCLE.SETTINGS.TOAST.CONCIERGE_SAVED'));
  } catch (e) {
    useAlert(e.message || 'Erro ao salvar concierge');
  }
};
</script>

<template>
  <div class="border border-n-slate-4 rounded-lg p-4">
    <div class="flex justify-between items-center cursor-pointer" @click="expanded = !expanded">
      <div>
        <div class="font-medium">{{ unit.name }}</div>
        <div class="text-xs text-n-slate-11">
          {{ unit.concierge_inbox_id ? '✓ configurado' : 'não configurado' }}
        </div>
      </div>
      <span>{{ expanded ? '▾' : '▸' }}</span>
    </div>

    <div v-if="expanded" class="mt-4 space-y-3">
      <label class="block text-sm">
        {{ t('CAPTAIN_LIFECYCLE.SETTINGS.CONCIERGE_INBOX') }}
        <select v-model="conciergeInboxId" class="w-full border rounded px-2 py-1">
          <option :value="null">—</option>
          <option v-for="ib in inboxes" :key="ib.id" :value="ib.id">{{ ib.name }}</option>
        </select>
      </label>

      <Input v-model="personaName" :label="t('CAPTAIN_LIFECYCLE.SETTINGS.CONCIERGE_PERSONA')" />

      <label class="block text-sm">
        {{ t('CAPTAIN_LIFECYCLE.SETTINGS.CONCIERGE_KNOWLEDGE') }}
        <textarea
          v-model="knowledge"
          rows="8"
          class="w-full border rounded p-2 font-mono text-xs"
        />
      </label>

      <div>
        <div class="text-sm font-medium mb-2">
          {{ t('CAPTAIN_LIFECYCLE.SETTINGS.CONCIERGE_VARIABLES') }}
        </div>
        <div v-for="(v, i) in variables" :key="i" class="flex gap-2 mb-2">
          <input
            v-model="v.k"
            :placeholder="t('CAPTAIN_LIFECYCLE.SETTINGS.CONCIERGE_VARIABLE_KEY')"
            class="border rounded px-2 py-1 w-1/3"
          />
          <input
            v-model="v.v"
            :placeholder="t('CAPTAIN_LIFECYCLE.SETTINGS.CONCIERGE_VARIABLE_VALUE')"
            class="border rounded px-2 py-1 flex-1"
          />
          <Button variant="ghost" size="sm" @click="removeVariable(i)">×</Button>
        </div>
        <Button variant="outline" size="sm" @click="addVariable">
          + {{ t('CAPTAIN_LIFECYCLE.SETTINGS.CONCIERGE_ADD_VARIABLE') }}
        </Button>
      </div>

      <Button @click="save">{{ t('CAPTAIN_LIFECYCLE.SETTINGS.SAVE') }}</Button>
    </div>
  </div>
</template>
```

**Nota:** verificar o nome exato do getter de inboxes WhatsApp. Se `inboxes/getWhatsAppInboxes` não existir, usar `inboxes/getInboxes` e filtrar por `channel_type === 'Channel::Whatsapp'`.

- [ ] **Step 2: Settings.vue (guards + lista de unidades)**

```vue
<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import Input from 'dashboard/components-next/input/Input.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Checkbox from 'dashboard/components-next/checkbox/Checkbox.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import ConciergeUnitCard from './components/ConciergeUnitCard.vue';

const store = useStore();
const { t } = useI18n();

const config = useMapGetter('captainLifecycleConfig/getConfig');
const uiFlags = useMapGetter('captainLifecycleConfig/getUIFlags');
const units = useMapGetter('captainUnits/getUnits');
const labels = useMapGetter('labels/getLabels');

const form = ref({});

const syncForm = () => {
  form.value = { ...config.value };
};

watch(config, syncForm, { immediate: true });

onMounted(() => {
  store.dispatch('captainLifecycleConfig/fetch');
  store.dispatch('captainUnits/get');
  store.dispatch('labels/get');
});

const save = async () => {
  try {
    await store.dispatch('captainLifecycleConfig/update', {
      quiet_hours_enabled: form.value.quiet_hours_enabled,
      quiet_hours_from: form.value.quiet_hours_from,
      quiet_hours_to: form.value.quiet_hours_to,
      min_interval_minutes: Number(form.value.min_interval_minutes),
      pause_on_customer_reply: form.value.pause_on_customer_reply,
      pause_on_customer_reply_within_minutes: Number(form.value.pause_on_customer_reply_within_minutes),
      opt_out_label_id: form.value.opt_out_label_id || null,
    });
    useAlert(t('CAPTAIN_LIFECYCLE.SETTINGS.TOAST.SAVED'));
  } catch (e) {
    useAlert(e.message || 'Erro');
  }
};
</script>

<template>
  <div class="p-6 space-y-8">
    <section>
      <h3 class="text-base font-semibold mb-3">
        {{ t('CAPTAIN_LIFECYCLE.SETTINGS.GUARDS_TITLE') }}
      </h3>
      <div v-if="uiFlags.fetching"><Spinner /></div>
      <div v-else class="space-y-3 max-w-xl">
        <Checkbox
          v-model="form.quiet_hours_enabled"
          :label="t('CAPTAIN_LIFECYCLE.SETTINGS.QUIET_HOURS_ENABLED')"
        />
        <div v-if="form.quiet_hours_enabled" class="flex gap-3">
          <label class="flex-1">
            {{ t('CAPTAIN_LIFECYCLE.SETTINGS.QUIET_HOURS_FROM') }}
            <input v-model="form.quiet_hours_from" type="time" class="w-full border rounded px-2 py-1" />
          </label>
          <label class="flex-1">
            {{ t('CAPTAIN_LIFECYCLE.SETTINGS.QUIET_HOURS_TO') }}
            <input v-model="form.quiet_hours_to" type="time" class="w-full border rounded px-2 py-1" />
          </label>
        </div>

        <Input
          v-model="form.min_interval_minutes"
          type="number"
          :label="t('CAPTAIN_LIFECYCLE.SETTINGS.MIN_INTERVAL')"
          :help-text="t('CAPTAIN_LIFECYCLE.SETTINGS.MIN_INTERVAL_HELP')"
        />

        <Checkbox
          v-model="form.pause_on_customer_reply"
          :label="t('CAPTAIN_LIFECYCLE.SETTINGS.PAUSE_ON_REPLY')"
        />
        <Input
          v-if="form.pause_on_customer_reply"
          v-model="form.pause_on_customer_reply_within_minutes"
          type="number"
          :label="t('CAPTAIN_LIFECYCLE.SETTINGS.PAUSE_ON_REPLY_WINDOW')"
        />

        <label class="block text-sm">
          {{ t('CAPTAIN_LIFECYCLE.SETTINGS.OPT_OUT_LABEL') }}
          <select v-model="form.opt_out_label_id" class="w-full border rounded px-2 py-1">
            <option :value="null">—</option>
            <option v-for="l in labels" :key="l.id" :value="l.id">{{ l.title }}</option>
          </select>
        </label>

        <p class="text-xs text-n-slate-11">
          {{ t('CAPTAIN_LIFECYCLE.SETTINGS.MAX_PER_RESERVATION_INFO') }}
        </p>

        <Button :disabled="uiFlags.updating" @click="save">
          {{ t('CAPTAIN_LIFECYCLE.SETTINGS.SAVE') }}
        </Button>
      </div>
    </section>

    <section>
      <h3 class="text-base font-semibold mb-3">
        {{ t('CAPTAIN_LIFECYCLE.SETTINGS.CONCIERGE_TITLE') }}
      </h3>
      <div class="space-y-3">
        <ConciergeUnitCard v-for="u in units" :key="u.id" :unit="u" />
      </div>
    </section>
  </div>
</template>
```

**Nota:** confirmar os nomes dos stores/getters (`captainUnits/get`, `labels/get`, etc). Se um getter não existir, ajustar pro que existe (checar `store/modules/inboxes.js`, `store/modules/labels.js`).

- [ ] **Step 3: Testar manualmente**

- Abrir `/captain/lifecycle/settings`
- Primeiro acesso cria config default (max_per_reservation 5 aparece, quiet_hours desligado)
- Mudar valores e salvar → toast de sucesso
- Recarregar a página → valores persistidos
- Expandir um card de unidade, preencher inbox + persona + knowledge + 1 variável, salvar → checar via console Rails: `account.captain_units.first.concierge_config`

- [ ] **Step 4: Eslint**

```bash
pnpm run eslint app/javascript/dashboard/routes/dashboard/captain/lifecycle/Settings.vue \
                app/javascript/dashboard/routes/dashboard/captain/lifecycle/components/ConciergeUnitCard.vue
```

- [ ] **Step 5: Commit**

```bash
git add app/javascript/dashboard/routes/dashboard/captain/lifecycle/Settings.vue \
        app/javascript/dashboard/routes/dashboard/captain/lifecycle/components/ConciergeUnitCard.vue
git commit -m "feat(lifecycle): settings tab with guards form and concierge per unit"
```

---

## Task 15: Tab Regras — lista + templates prontos + wizard

**Files:**
- Modify: `app/javascript/dashboard/routes/dashboard/captain/lifecycle/Rules.vue`
- Create: `app/javascript/dashboard/routes/dashboard/captain/lifecycle/components/RuleWizardDialog.vue`
- Create: `app/javascript/dashboard/routes/dashboard/captain/lifecycle/components/MessageEditor.vue`

- [ ] **Step 1: MessageEditor.vue — textarea com autocomplete de variáveis**

```vue
<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { AVAILABLE_VARIABLES } from '../constants';

const props = defineProps({
  modelValue: { type: String, default: '' },
});
const emit = defineEmits(['update:modelValue']);
const { t } = useI18n();

const textareaRef = ref(null);
const showAutocomplete = ref(false);
const autocompleteFilter = ref('');

const filteredVariables = computed(() => {
  const q = autocompleteFilter.value.toLowerCase();
  if (!q) return AVAILABLE_VARIABLES;
  return AVAILABLE_VARIABLES.filter(v => v.key.toLowerCase().includes(q));
});

const onInput = e => {
  const val = e.target.value;
  emit('update:modelValue', val);

  const caret = e.target.selectionStart;
  const before = val.slice(0, caret);
  const match = before.match(/\{\{\s*([a-zA-Z0-9_.]*)$/);
  if (match) {
    showAutocomplete.value = true;
    autocompleteFilter.value = match[1];
  } else {
    showAutocomplete.value = false;
  }
};

const insertVariable = key => {
  const ta = textareaRef.value;
  if (!ta) return;
  const val = props.modelValue;
  const caret = ta.selectionStart;
  const before = val.slice(0, caret).replace(/\{\{\s*[a-zA-Z0-9_.]*$/, '');
  const after = val.slice(caret);
  const inserted = `{{ ${key} }}`;
  emit('update:modelValue', before + inserted + after);
  showAutocomplete.value = false;
};
</script>

<template>
  <div class="relative">
    <textarea
      ref="textareaRef"
      :value="modelValue"
      rows="6"
      class="w-full border rounded p-2 font-mono text-sm"
      :placeholder="t('CAPTAIN_LIFECYCLE.RULES.WIZARD.FIELDS.MESSAGE_BODY')"
      @input="onInput"
    />

    <div
      v-if="showAutocomplete && filteredVariables.length"
      class="absolute z-20 mt-1 bg-n-solid-1 border border-n-slate-4 rounded shadow-lg max-h-60 overflow-auto w-80"
    >
      <button
        v-for="v in filteredVariables"
        :key="v.key"
        type="button"
        class="w-full text-left px-3 py-2 hover:bg-n-alpha-2 text-xs"
        @click="insertVariable(v.key)"
      >
        <span class="font-mono">{{ v.key }}</span>
        <span class="block text-n-slate-11">{{ v.descKey }}</span>
      </button>
    </div>
  </div>
</template>
```

- [ ] **Step 2: RuleWizardDialog.vue — 4 passos**

```vue
<script setup>
import { computed, ref, watch } from 'vue';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import Input from 'dashboard/components-next/input/Input.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Checkbox from 'dashboard/components-next/checkbox/Checkbox.vue';
import MessageEditor from './MessageEditor.vue';
import { EVENTS, MESSAGE_TYPES, OFFSET_UNITS } from '../constants';

const props = defineProps({
  rule: { type: Object, default: null },
});
const emit = defineEmits(['close', 'saved']);
const { t } = useI18n();
const store = useStore();

const units = useMapGetter('captainUnits/getUnits');

const step = ref(0);
const form = ref({
  name: '',
  description: '',
  event: 'checkin.scheduled_at',
  offset_value: 10,
  offset_unit: 'minutes',
  offset_direction: 'before',
  enabled: true,
  unit_ids: [],
  categorias: [],
  permanencias: [],
  message_type: 'text',
  message_body: '',
  priority: 50,
});

watch(() => props.rule, r => {
  if (!r) return;
  const direction = r.offset_minutes < 0 ? 'before' : 'after';
  const absMin = Math.abs(r.offset_minutes);
  const unit = absMin % 1440 === 0 ? 'days' : absMin % 60 === 0 ? 'hours' : 'minutes';
  const factor = OFFSET_UNITS.find(u => u.value === unit).factor;
  form.value = {
    name: r.name,
    description: r.description || '',
    event: r.event,
    offset_value: absMin / factor,
    offset_unit: unit,
    offset_direction: direction,
    enabled: r.enabled,
    unit_ids: r.filters?.unit_ids || [],
    categorias: r.filters?.categorias || [],
    permanencias: r.filters?.permanencias || [],
    message_type: r.message_type,
    message_body: r.message_body,
    priority: r.priority,
  };
}, { immediate: true });

const offsetMinutes = computed(() => {
  const factor = OFFSET_UNITS.find(u => u.value === form.value.offset_unit).factor;
  const sign = form.value.offset_direction === 'before' ? -1 : 1;
  return sign * Number(form.value.offset_value) * factor;
});

const canNext = computed(() => {
  if (step.value === 0) return !!form.value.event && !!form.value.offset_value;
  if (step.value === 1) return form.value.unit_ids.length > 0;
  if (step.value === 2) return !!form.value.name && !!form.value.message_body;
  return true;
});

const next = () => step.value < 3 && (step.value += 1);
const back = () => step.value > 0 && (step.value -= 1);

const save = async () => {
  const payload = {
    name: form.value.name,
    description: form.value.description,
    event: form.value.event,
    offset_minutes: offsetMinutes.value,
    enabled: form.value.enabled,
    filters: {
      unit_ids: form.value.unit_ids,
      categorias: form.value.categorias,
      permanencias: form.value.permanencias,
    },
    message_type: form.value.message_type,
    message_body: form.value.message_body,
    priority: Number(form.value.priority),
  };
  try {
    if (props.rule?.id) {
      await store.dispatch('captainLifecycleRules/update', { id: props.rule.id, ...payload });
      useAlert(t('CAPTAIN_LIFECYCLE.RULES.TOAST.UPDATED'));
    } else {
      await store.dispatch('captainLifecycleRules/create', payload);
      useAlert(t('CAPTAIN_LIFECYCLE.RULES.TOAST.CREATED'));
    }
    emit('saved');
  } catch (e) {
    useAlert(e.message || 'Erro');
  }
};
</script>

<template>
  <div class="fixed inset-0 z-50 flex items-center justify-center bg-black/40" @click.self="emit('close')">
    <div class="bg-n-solid-1 rounded-xl p-6 w-[680px] max-h-[90vh] overflow-auto shadow-xl">
      <h3 class="text-lg font-semibold mb-4">
        {{ props.rule ? t('CAPTAIN_LIFECYCLE.RULES.WIZARD.TITLE_EDIT') : t('CAPTAIN_LIFECYCLE.RULES.WIZARD.TITLE_CREATE') }}
      </h3>

      <ol class="flex gap-2 mb-6 text-xs">
        <li :class="step === 0 ? 'font-bold' : ''">1. {{ t('CAPTAIN_LIFECYCLE.RULES.WIZARD.STEP_WHEN') }}</li>
        <li :class="step === 1 ? 'font-bold' : ''">2. {{ t('CAPTAIN_LIFECYCLE.RULES.WIZARD.STEP_WHO') }}</li>
        <li :class="step === 2 ? 'font-bold' : ''">3. {{ t('CAPTAIN_LIFECYCLE.RULES.WIZARD.STEP_WHAT') }}</li>
        <li :class="step === 3 ? 'font-bold' : ''">4. {{ t('CAPTAIN_LIFECYCLE.RULES.WIZARD.STEP_REVIEW') }}</li>
      </ol>

      <!-- Step 0: When -->
      <div v-if="step === 0" class="space-y-3">
        <label class="block">
          {{ t('CAPTAIN_LIFECYCLE.RULES.WIZARD.FIELDS.EVENT') }}
          <select v-model="form.event" class="w-full border rounded px-2 py-1">
            <option v-for="e in EVENTS" :key="e.value" :value="e.value">{{ t(e.labelKey) }}</option>
          </select>
        </label>
        <div class="grid grid-cols-3 gap-3">
          <Input v-model="form.offset_value" type="number" :label="t('CAPTAIN_LIFECYCLE.RULES.WIZARD.FIELDS.OFFSET_VALUE')" />
          <label class="block">
            {{ t('CAPTAIN_LIFECYCLE.RULES.WIZARD.FIELDS.OFFSET_UNIT') }}
            <select v-model="form.offset_unit" class="w-full border rounded px-2 py-1">
              <option v-for="u in OFFSET_UNITS" :key="u.value" :value="u.value">
                {{ t(`CAPTAIN_LIFECYCLE.RULES.WIZARD.OFFSET_UNITS.${u.value.toUpperCase()}`) }}
              </option>
            </select>
          </label>
          <label class="block">
            {{ t('CAPTAIN_LIFECYCLE.RULES.WIZARD.FIELDS.OFFSET_DIRECTION') }}
            <select v-model="form.offset_direction" class="w-full border rounded px-2 py-1">
              <option value="before">{{ t('CAPTAIN_LIFECYCLE.RULES.WIZARD.OFFSET_DIRECTIONS.BEFORE') }}</option>
              <option value="after">{{ t('CAPTAIN_LIFECYCLE.RULES.WIZARD.OFFSET_DIRECTIONS.AFTER') }}</option>
            </select>
          </label>
        </div>
      </div>

      <!-- Step 1: Who -->
      <div v-else-if="step === 1" class="space-y-3">
        <label class="block">
          {{ t('CAPTAIN_LIFECYCLE.RULES.WIZARD.FIELDS.UNITS') }}
          <div class="space-y-1 mt-2">
            <label v-for="u in units" :key="u.id" class="flex items-center gap-2 text-sm">
              <input type="checkbox" :value="u.id" v-model="form.unit_ids" />
              {{ u.name }}
            </label>
          </div>
        </label>
        <Input
          v-model="form.categorias"
          :label="t('CAPTAIN_LIFECYCLE.RULES.WIZARD.FIELDS.CATEGORIAS')"
          placeholder="Alexa, Stilo (separar por vírgula)"
          @update:model-value="v => form.categorias = typeof v === 'string' ? v.split(',').map(s => s.trim()).filter(Boolean) : v"
        />
        <Input
          v-model="form.permanencias"
          :label="t('CAPTAIN_LIFECYCLE.RULES.WIZARD.FIELDS.PERMANENCIAS')"
          placeholder="Pernoite, 2hrs"
          @update:model-value="v => form.permanencias = typeof v === 'string' ? v.split(',').map(s => s.trim()).filter(Boolean) : v"
        />
      </div>

      <!-- Step 2: What -->
      <div v-else-if="step === 2" class="space-y-3">
        <Input v-model="form.name" :label="t('CAPTAIN_LIFECYCLE.RULES.WIZARD.FIELDS.NAME')" />
        <Input v-model="form.description" :label="t('CAPTAIN_LIFECYCLE.RULES.WIZARD.FIELDS.DESCRIPTION')" />
        <label class="block">
          {{ t('CAPTAIN_LIFECYCLE.RULES.WIZARD.FIELDS.MESSAGE_TYPE') }}
          <select v-model="form.message_type" class="w-full border rounded px-2 py-1">
            <option v-for="m in MESSAGE_TYPES" :key="m.value" :value="m.value">{{ t(m.labelKey) }}</option>
          </select>
        </label>
        <div>
          <div class="text-sm mb-1">{{ t('CAPTAIN_LIFECYCLE.RULES.WIZARD.FIELDS.MESSAGE_BODY') }}</div>
          <MessageEditor v-model="form.message_body" />
        </div>
        <Checkbox v-model="form.enabled" :label="t('CAPTAIN_LIFECYCLE.RULES.WIZARD.FIELDS.ENABLED')" />
      </div>

      <!-- Step 3: Review -->
      <div v-else class="space-y-2 text-sm">
        <div><strong>Nome:</strong> {{ form.name }}</div>
        <div><strong>Evento:</strong> {{ form.event }}</div>
        <div><strong>Offset (min):</strong> {{ offsetMinutes }}</div>
        <div><strong>Unidades:</strong> {{ form.unit_ids.join(', ') }}</div>
        <div><strong>Mensagem:</strong></div>
        <pre class="p-3 bg-n-alpha-2 rounded whitespace-pre-wrap">{{ form.message_body }}</pre>
      </div>

      <div class="flex justify-between mt-6">
        <Button variant="outline" :disabled="step === 0" @click="back">
          {{ t('CAPTAIN_LIFECYCLE.RULES.WIZARD.BACK') }}
        </Button>
        <div class="flex gap-2">
          <Button variant="outline" @click="emit('close')">Cancelar</Button>
          <Button v-if="step < 3" :disabled="!canNext" @click="next">
            {{ t('CAPTAIN_LIFECYCLE.RULES.WIZARD.NEXT') }}
          </Button>
          <Button v-else @click="save">
            {{ t('CAPTAIN_LIFECYCLE.RULES.WIZARD.SAVE') }}
          </Button>
        </div>
      </div>
    </div>
  </div>
</template>
```

- [ ] **Step 3: Rules.vue — lista + templates + botão**

```vue
<script setup>
import { computed, onMounted, ref } from 'vue';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import RuleWizardDialog from './components/RuleWizardDialog.vue';
import { RULE_TEMPLATES } from './constants';

const store = useStore();
const { t } = useI18n();

const rules = useMapGetter('captainLifecycleRules/getRecords');
const uiFlags = useMapGetter('captainLifecycleRules/getUIFlags');

const showWizard = ref(false);
const editing = ref(null);

onMounted(() => {
  store.dispatch('captainLifecycleRules/get');
  store.dispatch('captainUnits/get');
});

const openCreate = () => {
  editing.value = null;
  showWizard.value = true;
};
const openEdit = rule => {
  editing.value = rule;
  showWizard.value = true;
};
const openFromTemplate = tpl => {
  editing.value = {
    id: null,
    name: tpl.name,
    event: tpl.event,
    offset_minutes: tpl.offset_minutes,
    message_type: tpl.message_type,
    message_body: tpl.message_body,
    enabled: true,
    filters: {},
    priority: 50,
  };
  showWizard.value = true;
};
const onSaved = () => {
  showWizard.value = false;
  store.dispatch('captainLifecycleRules/get');
};
const toggle = async rule => {
  await store.dispatch('captainLifecycleRules/update', { id: rule.id, enabled: !rule.enabled });
};
const remove = async rule => {
  if (!confirm(t('CAPTAIN_LIFECYCLE.RULES.DELETE_CONFIRM'))) return;
  await store.dispatch('captainLifecycleRules/delete', rule.id);
  useAlert(t('CAPTAIN_LIFECYCLE.RULES.TOAST.DELETED'));
};

const isLoading = computed(() => uiFlags.value.fetchingList);
</script>

<template>
  <div class="p-6 space-y-6">
    <section>
      <h3 class="text-sm font-semibold mb-3 text-n-slate-11">
        {{ t('CAPTAIN_LIFECYCLE.RULES.TEMPLATES_TITLE') }}
      </h3>
      <div class="grid grid-cols-3 gap-3">
        <button
          v-for="tpl in RULE_TEMPLATES"
          :key="tpl.id"
          type="button"
          class="text-left p-3 border border-n-slate-4 rounded-lg hover:border-n-iris-9"
          @click="openFromTemplate(tpl)"
        >
          <div class="font-medium text-sm">{{ tpl.name }}</div>
          <div class="text-xs text-n-slate-11 mt-1">{{ tpl.event }} {{ tpl.offset_minutes >= 0 ? '+' : '' }}{{ tpl.offset_minutes }}min</div>
        </button>
      </div>
    </section>

    <section>
      <div class="flex justify-between items-center mb-3">
        <h3 class="text-base font-semibold">Regras</h3>
        <Button @click="openCreate">{{ t('CAPTAIN_LIFECYCLE.RULES.CREATE') }}</Button>
      </div>

      <div v-if="isLoading"><Spinner /></div>
      <div v-else-if="rules.length === 0" class="text-center py-8 text-n-slate-11">
        {{ t('CAPTAIN_LIFECYCLE.RULES.EMPTY') }}
      </div>
      <table v-else class="w-full text-sm">
        <thead class="text-left text-n-slate-11">
          <tr>
            <th class="py-2">{{ t('CAPTAIN_LIFECYCLE.RULES.COLUMNS.NAME') }}</th>
            <th>{{ t('CAPTAIN_LIFECYCLE.RULES.COLUMNS.EVENT') }}</th>
            <th>{{ t('CAPTAIN_LIFECYCLE.RULES.COLUMNS.OFFSET') }}</th>
            <th>{{ t('CAPTAIN_LIFECYCLE.RULES.COLUMNS.STATUS') }}</th>
            <th>{{ t('CAPTAIN_LIFECYCLE.RULES.COLUMNS.ACTIONS') }}</th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="r in rules" :key="r.id" class="border-t border-n-slate-4">
            <td class="py-2">{{ r.name }}</td>
            <td>{{ r.event }}</td>
            <td>{{ r.offset_minutes }}min</td>
            <td>
              {{ r.enabled
                ? t('CAPTAIN_LIFECYCLE.RULES.STATUS.ENABLED')
                : t('CAPTAIN_LIFECYCLE.RULES.STATUS.DISABLED') }}
            </td>
            <td class="flex gap-2">
              <Button size="sm" variant="ghost" @click="openEdit(r)">
                {{ t('CAPTAIN_LIFECYCLE.RULES.ACTIONS.EDIT') }}
              </Button>
              <Button size="sm" variant="ghost" @click="toggle(r)">
                {{ t('CAPTAIN_LIFECYCLE.RULES.ACTIONS.TOGGLE') }}
              </Button>
              <Button size="sm" variant="ghost" @click="remove(r)">
                {{ t('CAPTAIN_LIFECYCLE.RULES.ACTIONS.DELETE') }}
              </Button>
            </td>
          </tr>
        </tbody>
      </table>
    </section>

    <RuleWizardDialog
      v-if="showWizard"
      :rule="editing"
      @close="showWizard = false"
      @saved="onSaved"
    />
  </div>
</template>
```

- [ ] **Step 4: Testar manualmente ponta-a-ponta**

- `/captain/lifecycle/rules` → vazia, mostra templates + botão "Nova regra"
- Clicar em um template → wizard abre com campos pré-preenchidos no passo 3 (mas começa no passo 0 de qualquer forma)
- Preencher wizard, chegar no review, salvar → toast criado, regra aparece na lista
- Editar → wizard abre com os valores, alterar nome, salvar → toast atualizado
- No campo de mensagem, digitar `{{` → autocomplete aparece, clicar numa variável → texto preenchido corretamente
- Excluir → confirmação, toast, some da lista
- Refresh → persiste

- [ ] **Step 5: Eslint**

```bash
pnpm run eslint app/javascript/dashboard/routes/dashboard/captain/lifecycle/Rules.vue \
                app/javascript/dashboard/routes/dashboard/captain/lifecycle/components/RuleWizardDialog.vue \
                app/javascript/dashboard/routes/dashboard/captain/lifecycle/components/MessageEditor.vue \
                app/javascript/dashboard/routes/dashboard/captain/lifecycle/constants.js
```

- [ ] **Step 6: Commit**

```bash
git add app/javascript/dashboard/routes/dashboard/captain/lifecycle/Rules.vue \
        app/javascript/dashboard/routes/dashboard/captain/lifecycle/components/RuleWizardDialog.vue \
        app/javascript/dashboard/routes/dashboard/captain/lifecycle/components/MessageEditor.vue \
        app/javascript/dashboard/routes/dashboard/captain/lifecycle/constants.js
git commit -m "feat(lifecycle): rules tab with templates, wizard and variable autocomplete"
```

---

## Task 16: Validação final — specs + lint + smoke manual

**Files:** nenhum novo.

- [ ] **Step 1: Rodar suite lifecycle (backend + novos controllers)**

```bash
eval "$(rbenv init - zsh)" && rbenv shell 3.4.4 && bundle exec rspec \
  spec/models/account_spec.rb \
  spec/routing/captain_lifecycle_routes_spec.rb \
  spec/enterprise/policies/captain/lifecycle \
  spec/enterprise/controllers/api/v1/accounts/captain/lifecycle_rules_controller_spec.rb \
  spec/enterprise/controllers/api/v1/accounts/captain/lifecycle_configs_controller_spec.rb \
  spec/enterprise/controllers/api/v1/accounts/captain/lifecycle_deliveries_controller_spec.rb \
  spec/enterprise/controllers/api/v1/accounts/captain/units_controller_spec.rb \
  spec/enterprise/models/captain/lifecycle \
  spec/enterprise/services/captain/lifecycle \
  spec/enterprise/jobs/captain/lifecycle
```
Esperado: 0 failures.

- [ ] **Step 2: Regression gate**

```bash
bundle exec rspec spec/enterprise/models/captain/reservation_spec.rb \
                  spec/models/account_spec.rb
bundle exec rubocop app/models/account.rb \
                    enterprise/app/controllers/api/v1/accounts/captain/lifecycle_rules_controller.rb \
                    enterprise/app/controllers/api/v1/accounts/captain/lifecycle_configs_controller.rb \
                    enterprise/app/controllers/api/v1/accounts/captain/lifecycle_deliveries_controller.rb \
                    enterprise/app/controllers/api/v1/accounts/captain/units_controller.rb \
                    enterprise/app/policies/captain/lifecycle
```
Esperado: green.

- [ ] **Step 3: Lint frontend completo da nova área**

```bash
pnpm run eslint app/javascript/dashboard/routes/dashboard/captain/lifecycle \
                app/javascript/dashboard/api/captain/lifecycleRules.js \
                app/javascript/dashboard/api/captain/lifecycleConfig.js \
                app/javascript/dashboard/api/captain/lifecycleDeliveries.js \
                app/javascript/dashboard/store/captain/lifecycleRules.js \
                app/javascript/dashboard/store/captain/lifecycleConfig.js \
                app/javascript/dashboard/store/captain/lifecycleDeliveries.js \
                app/javascript/dashboard/components-next/sidebar/Sidebar.vue
```
Esperado: 0 errors.

- [ ] **Step 4: Smoke end-to-end manual**

Com `pnpm run dev` rodando e uma conta de teste:

1. Sidebar → Captain → "Jornada do Cliente" → abre na tab Regras
2. Criar regra de template "Lembrete pré check-in" → preencher wizard → salvar
3. Tab Configurações → habilitar quiet hours 22:00-08:00, salvar → toast
4. Expandir card da primeira unit → setar inbox, persona "Sofia", adicionar 1 variável wifi_password → salvar → toast
5. Via console Rails: `Captain::Reservation.create!(account: ..., unit: ..., contact: ..., check_in_at: 15.minutes.from_now, ...)` — delivery é agendada automaticamente
6. Tab Histórico → ver delivery com status `scheduled`, clicar "Preview" → modal com rendered body vazio (ainda não disparou)
7. Voltar no console: `Captain::Lifecycle::DispatcherJob.perform_now(delivery.id)` → delivery passa pra `sent` ou `skipped` (conforme guards)
8. Refresh tab Histórico → status atualizado, preview mostra rendered body com variáveis substituídas
9. Voltar em Regras → desativar a regra pelo botão "Ativar/Desativar" → status muda pra "Desativado"
10. Excluir a regra → confirmação, some da lista

Se algum passo falhar, diagnosticar via:
- DevTools console do browser
- `tail -f log/development.log` no Rails
- Checar delivery row direto via console: `Captain::Lifecycle::Delivery.last`

- [ ] **Step 5: Commit final (se necessário) + handoff**

Se tudo verde, sem commits extras. Caso haja pequenas correções durante smoke:

```bash
git add -u
git commit -m "fix(lifecycle): smoke test adjustments"
```

**Entregar pro user:** "Fase B (UI Jornada do Cliente) completa. Rodei specs + lint + smoke ponta-a-ponta. [Listar ajustes feitos durante smoke, se algum]."

---

## Notas finais

- **Accessibilidade:** o plano usa `<select>`, `<textarea>`, `<input type="checkbox">` nativos pra simplicidade. Pode ser melhorado depois pra componentes acessíveis do design system.
- **Dark mode:** as classes `bg-n-solid-1`, `text-n-slate-11`, `border-n-slate-4` são tokens do Chatwoot e já cobrem light/dark. Não inventar cores hex.
- **`fazer.ai` minúsculo:** nenhuma copy introduzida no plano menciona a marca, mas se surgir no smoke ou em toasts: sempre `fazer.ai`.
- **Tests Vitest:** não há specs de component Vue neste plano porque o projeto não tem cobertura histórica de components Captain. Se o reviewer quiser, um spec mínimo pra `MessageEditor` (insertVariable unit test) é viável — fora do escopo por decisão de pragmatismo.
- **Nomes de getters de unit/label/inbox:** verificar os exatos (`captainUnits/getUnits`, `labels/getLabels`, `inboxes/getWhatsAppInboxes`) durante implementação; se divergirem, ajustar inline sem reescrever o plano.
