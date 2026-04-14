# Reserva Rede 1001 — Fase 2+3: Backend Chatwoot + Fluxo Público Completo

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Fluxo completo onde o cliente abre a página `reserva-1001`, escolhe marca → unidade → permanência → categoria → data → vê fotos + preço, preenche seus dados, clica "Confirmar e Pagar" e recebe um **QR Code PIX real gerado pela API do Chatwoot** (que chama a Inter), paga, e a página detecta o pagamento via polling. No Chatwoot a atendente recebe uma mensagem automática "✅ Pagamento confirmado!" na conversa.

**Architecture (2 partes):**
1. **Backend (Chatwoot)**: controller público novo `Public::Api::V1::Captain::PublicReservationsController` com 2 endpoints (POST cria reserva + PIX, GET retorna status). Reusa 100% do `Captain::Inter::CobService`, `ConfirmationService` e webhook Inter existentes.
2. **Frontend (reserva-1001)**: refatora `App.tsx` em fluxo multi-step, adiciona hook `useReservationForm`, services do Supabase (unidades/categorias/preços/fotos), componentes de form em cascata, tela de checkout com polling, tela de sucesso.

**Tech Stack:** Rails 7 (backend) · React 19 + TypeScript + Supabase (frontend) · Inter API (PIX, via Chatwoot) · RSpec · Vitest

**Spec:** `docs/superpowers/specs/2026-04-13-reserva-1001-design.md`
**Fase 1 (pré-requisito):** `docs/superpowers/plans/2026-04-13-reserva-1001-fase-1-fundacao.md` — COMPLETO

---

## Dados conhecidos (já investigados)

**Chatwoot dev DB:**
- `Captain::Unit` id=4, name="Hotel 1001 Águas Lindas", account_id=1, inbox_id=2, **Inter credentials completas (client_id/secret/cert/key/pix_key)** → usar como unidade de teste.
- Unit id=3 "Hotel Recanto" tem inbox_id=1 como segunda opção.

**Modelos Chatwoot relevantes:**
- `Captain::Reservation` (`enterprise/app/models/captain/reservation.rb`) — campos obrigatórios: `account`, `inbox`, `contact`, `contact_inbox`, `suite_identifier`, `check_in_at`, `check_out_at`. Enum status: `{scheduled:0, active:1, completed:2, cancelled:3, pending_payment:4, draft:5, confirmed:6}`. `payment_status` é string ('pending'/'paid').
- `Captain::PixCharge` (`enterprise/app/models/captain/pix_charge.rb`) — `txid`, `pix_copia_e_cola`, `status` enum `{active, paid, expired, failed}`, pertence a `Reservation` e `Unit`.
- `Captain::Inter::CobService#call` — assinatura: `initialize(reservation, amount: nil)`. Retorna `Captain::PixCharge`. Atualiza `reservation.current_pix_charge_id`.
- `Captain::Payments::ConfirmationService#perform` — marca reservation paga, adiciona labels, cria mensagem automática na conversa.

**Builders:**
- `ContactInboxWithContactBuilder.new(source_id:, inbox:, contact_attributes:).perform` — cria/dedupe contact + contact_inbox.
- `ConversationBuilder.new(params:, contact_inbox:).perform` — cria conversation.
- `Messages::MessageBuilder.new(user, conversation, params).perform` — cria mensagem.

**Rotas existentes:**
- Webhook Inter: `POST /api/v1/captain/webhooks/inter_pix` (público, sem auth)
- Short payment link: `GET /r/:token`

**Supabase `reserva_hotel` (hoje):**
- `marcas`: 1 row ("Hotel 1001 Noites", categorias=["Standard","Superior","Luxo"], permanencias=["3hrs","6hrs","Pernoite"])
- `unidades`, `precos`, `fotos_categoria`: 0 rows cada
- Task A0 (seed) popula isso com dados de teste.

---

## File Structure

**Backend (dentro de `chatwoot/`):**
```
enterprise/app/controllers/public/api/v1/captain/
└── public_reservations_controller.rb     # novo

config/routes.rb                           # adicionar 2 rotas

spec/enterprise/controllers/public/api/v1/captain/
└── public_reservations_controller_spec.rb # novo
```

**Frontend (dentro de `reserva-1001/src/`):**
```
lib/
├── chatwootApi.ts          # novo — client HTTP do endpoint novo
├── formatters.ts           # novo — utilidades BRL, CPF, tel
└── supabase.ts             # existente

services/                    # NOVO
├── unidadesService.ts      # lista unidades por marca
├── categoriasService.ts    # resolve categorias visíveis por unidade
├── precosService.ts        # resolve preço por categoria+permanência+day_range
└── fotosService.ts         # fotos por unidade+categoria

hooks/                       # NOVO
└── useReservationForm.ts   # estado consolidado do form

components/
├── FormField.tsx            # existente
├── SelectField.tsx          # existente
├── reservation/             # NOVO
│   ├── ReservationFlow.tsx  # orquestra as etapas
│   ├── StayDetailsStep.tsx  # marca→unidade→permanência→categoria→data
│   ├── ImageGallery.tsx     # grid de fotos
│   ├── PriceSummary.tsx     # preço total + 50% PIX
│   ├── CustomerForm.tsx     # nome/tel/CPF/email/obs
│   └── SubmitButton.tsx
├── checkout/                # NOVO
│   ├── PixCheckout.tsx      # QR + copia-cola + timer + polling
│   └── SuccessScreen.tsx    # confirmação
└── ui/
    └── button.tsx           # existente

App.tsx                      # reescrito pra montar ReservationFlow / PixCheckout / SuccessScreen
```

---

## Pré-requisitos (informações que eu, controller, tenho antes de dispatchar qualquer subagente)

1. **Credenciais Supabase** já em `reserva-1001/.env.local` (Fase 1 feita)
2. **Chatwoot dev rodando** em `http://localhost:3000` (para Fase 2 testar o endpoint via curl e para Fase 3 bater contra)
3. **Captain::Unit id=4 (Hotel 1001 Águas Lindas)** é a unidade de teste conhecida, inbox_id=2, account_id=1
4. **Token de autenticação do endpoint público**: vamos definir `RESERVA_1001_API_TOKEN=dev-token-change-in-prod` em `chatwoot/.env` (dev) e `reserva-1001/.env.local` (VITE_CHATWOOT_API_TOKEN)

---

# PARTE A — Dados de teste (Supabase seed)

## Task A0: Seed de dados de teste em `reserva_hotel`

**Contexto:** Sem unidade, preços e fotos no Supabase, o frontend não tem o que renderizar. Esta task popula o mínimo necessário pra testar todo o fluxo com a unidade Hotel 1001 Águas Lindas (Captain::Unit id=4 no Chatwoot).

**Files:**
- Create: `reserva-1001/supabase/migrations/20260413000002_seed_dados_teste.sql`

- [ ] **Step 1: Aplicar seed via MCP (apply_migration)**

Migration name: `reserva_1001_seed_dados_teste`

Query SQL:
```sql
-- Usa a marca já existente ("Hotel 1001 Noites") e cria:
--  • 1 unidade (Águas Lindas) amarrada ao Captain::Unit id=4
--  • 6 preços (2 categorias × 3 permanências, weekday)
--  • 4 fotos por categoria (URLs placeholders do Unsplash)
--  • 2 extras (adicional tira-gosto + decoração romântica)

do $$
declare
  v_marca_id  uuid;
  v_unidade_id uuid;
begin
  -- 1. Garante que a marca tem categorias e permanências coerentes com os preços
  select id into v_marca_id from reserva_hotel.marcas where nome = 'Hotel 1001 Noites' limit 1;

  if v_marca_id is null then
    insert into reserva_hotel.marcas (nome, categorias, permanencias, ativa)
    values ('Hotel 1001 Noites',
            array['Standard','Hidromassagem'],
            array['3hrs','4hrs','Pernoite'],
            true)
    returning id into v_marca_id;
  else
    update reserva_hotel.marcas
       set categorias = array['Standard','Hidromassagem'],
           permanencias = array['3hrs','4hrs','Pernoite']
     where id = v_marca_id;
  end if;

  -- 2. Unidade amarrada ao Captain::Unit id=4
  insert into reserva_hotel.unidades
    (nome, id_marca, id_conta_pagamento, categorias_visiveis,
     endereco, telefone, ativa, chatwoot_unit_id)
  select
    'Hotel 1001 Águas Lindas',
    v_marca_id,
    (select id from reserva_hotel.contas_pagamento limit 1),
    array['Standard','Hidromassagem'],
    'Águas Lindas, GO',
    '(61) 99999-0000',
    true,
    4
  on conflict do nothing
  returning id into v_unidade_id;

  if v_unidade_id is null then
    select id into v_unidade_id
      from reserva_hotel.unidades
     where chatwoot_unit_id = 4
     limit 1;
  end if;

  -- 3. Preços (6 rows: 2 categorias × 3 permanências) — weekday default
  insert into reserva_hotel.precos
    (id_marca, categoria, permanencia, periodo_semana, valor, ativo)
  values
    (v_marca_id, 'Standard',       '3hrs',     'default', 120.00, true),
    (v_marca_id, 'Standard',       '4hrs',     'default', 150.00, true),
    (v_marca_id, 'Standard',       'Pernoite', 'default', 220.00, true),
    (v_marca_id, 'Hidromassagem',  '3hrs',     'default', 170.00, true),
    (v_marca_id, 'Hidromassagem',  '4hrs',     'default', 210.00, true),
    (v_marca_id, 'Hidromassagem',  'Pernoite', 'default', 290.00, true)
  on conflict do nothing;

  -- 4. Fotos (URLs placeholder Unsplash, 2 por categoria)
  insert into reserva_hotel.fotos_categoria
    (id_unidade, categoria, url_foto, alt, ordem)
  values
    (v_unidade_id, 'Standard',
      'https://images.unsplash.com/photo-1631049307264-da0ec9d70304?w=800', 'Suíte Standard vista 1', 0),
    (v_unidade_id, 'Standard',
      'https://images.unsplash.com/photo-1590490360182-c33d57733427?w=800', 'Suíte Standard vista 2', 1),
    (v_unidade_id, 'Hidromassagem',
      'https://images.unsplash.com/photo-1582719508461-905c673771fd?w=800', 'Suíte Hidromassagem vista 1', 0),
    (v_unidade_id, 'Hidromassagem',
      'https://images.unsplash.com/photo-1578683010236-d716f9a3f461?w=800', 'Suíte Hidromassagem vista 2', 1)
  on conflict do nothing;

  -- 5. Extras simples
  insert into reserva_hotel.extras
    (id_marca, titulo, descricao, preco, ativo, ordem)
  values
    (v_marca_id, 'Tira-gosto', 'Porção de petiscos servida na suíte', 35.00, true, 0),
    (v_marca_id, 'Decoração romântica', 'Pétalas, velas e champanhe', 90.00, true, 1)
  on conflict do nothing;
end $$;
```

*(Controller nota: aplicar via `mcp__claude_ai_supabase__apply_migration` com project_id `acdvblhzzaneddlxqyst`, name `reserva_1001_seed_dados_teste`.)*

- [ ] **Step 2: Validar que os dados estão lá**

Query via MCP `execute_sql`:
```sql
select
  (select count(*) from reserva_hotel.unidades where chatwoot_unit_id=4) as unidades,
  (select count(*) from reserva_hotel.precos) as precos,
  (select count(*) from reserva_hotel.fotos_categoria) as fotos,
  (select count(*) from reserva_hotel.extras) as extras;
```

Expected: `unidades=1, precos=6, fotos=4, extras=2`.

- [ ] **Step 3: Commit do arquivo de migration**

```bash
cd /Users/user/Dev/Produtos/Chatwoot-fazer-ai/fazer-ai-kanban/reserva-1001
git add supabase/migrations/20260413000002_seed_dados_teste.sql
git commit -m "feat: seed de dados de teste (unidade aguas lindas, precos, fotos, extras)"
```

---

# PARTE B — Backend Chatwoot (Fase 2)

## Task B1: Variável de ambiente para o token

**Files:**
- Modify: `chatwoot/.env` (não commitar — só local)
- Modify: `chatwoot/.env.example` (commitar)

- [ ] **Step 1: Adicionar ao `.env` local**

Append a `chatwoot/.env`:
```
# Reserva Rede 1001 — Public API token
RESERVA_1001_API_TOKEN=dev-token-change-in-prod
```

- [ ] **Step 2: Adicionar ao `.env.example`**

Append a `chatwoot/.env.example`:
```
# Reserva Rede 1001 — public reservations API (Fase 2)
# Token usado para autenticar chamadas do app reserva-1001 ao endpoint publico
# de geracao de reservas/PIX. Gerar via `openssl rand -hex 32` em producao.
RESERVA_1001_API_TOKEN=
```

- [ ] **Step 3: Commit apenas o `.env.example`**

```bash
cd /Users/user/Dev/Produtos/Chatwoot-fazer-ai/fazer-ai-kanban/chatwoot
git add .env.example
git commit -m "chore: documenta RESERVA_1001_API_TOKEN no .env.example"
```

---

## Task B2: Teste RSpec — autenticação por token

**Files:**
- Create: `chatwoot/spec/enterprise/controllers/public/api/v1/captain/public_reservations_controller_spec.rb`

- [ ] **Step 1: Criar o spec com o primeiro teste (TDD — falha porque controller ainda não existe)**

Create `spec/enterprise/controllers/public/api/v1/captain/public_reservations_controller_spec.rb`:
```ruby
require 'rails_helper'

RSpec.describe 'Public Captain Reservations API', type: :request do
  let(:unit) { create(:captain_unit, account: create(:account)) }
  let(:valid_token) { 'test-token-abc' }

  before do
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with('RESERVA_1001_API_TOKEN', any_args).and_return(valid_token)
  end

  describe 'POST /public/api/v1/captain/public_reservations' do
    context 'without token' do
      it 'returns 401' do
        post '/public/api/v1/captain/public_reservations',
             params: { chatwoot_unit_id: unit.id }.to_json,
             headers: { 'Content-Type' => 'application/json' }

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'with invalid token' do
      it 'returns 401' do
        post '/public/api/v1/captain/public_reservations',
             params: { chatwoot_unit_id: unit.id }.to_json,
             headers: {
               'Content-Type' => 'application/json',
               'X-Reserva-Token' => 'wrong'
             }

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end
end
```

- [ ] **Step 2: Rodar o spec (deve falhar — rota/controller não existem)**

```bash
cd /Users/user/Dev/Produtos/Chatwoot-fazer-ai/fazer-ai-kanban/chatwoot
bundle exec rspec spec/enterprise/controllers/public/api/v1/captain/public_reservations_controller_spec.rb 2>&1 | tail -20
```

Expected: FAILURE — rota não existe.

- [ ] **Step 3: Commit do spec falhando**

```bash
git add spec/enterprise/controllers/public/api/v1/captain/public_reservations_controller_spec.rb
git commit -m "test: spec para autenticacao do PublicReservationsController (red)"
```

---

## Task B3: Rota + controller esqueleto com autenticação

**Files:**
- Modify: `chatwoot/config/routes.rb`
- Create: `chatwoot/enterprise/app/controllers/public/api/v1/captain/public_reservations_controller.rb`

- [ ] **Step 1: Ler o `config/routes.rb` atual e encontrar o namespace público**

```bash
cd /Users/user/Dev/Produtos/Chatwoot-fazer-ai/fazer-ai-kanban/chatwoot
grep -n "public/api/v1/captain" config/routes.rb
```

Expected: mostra a linha do `inter_webhooks`. A nova rota vai logo abaixo.

- [ ] **Step 2: Adicionar rota**

Edit `config/routes.rb` — encontrar o bloco que registra `inter_pix` webhook (algo como `post '/api/v1/captain/webhooks/inter_pix', to: 'public/api/v1/captain/inter_webhooks#create'`) e adicionar na sequência:

```ruby
# Reserva Rede 1001 — public reservation API
namespace :public, defaults: { format: 'json' } do
  namespace :api do
    namespace :v1 do
      namespace :captain do
        resources :public_reservations, only: [:create, :show] do
          member do
            get :status
          end
        end
      end
    end
  end
end
```

Se já existir um namespace `public/api/v1/captain` aberto por outro motivo, colocar o `resources :public_reservations` dentro dele.

- [ ] **Step 3: Criar o controller com auth-only**

Create `enterprise/app/controllers/public/api/v1/captain/public_reservations_controller.rb`:
```ruby
class Public::Api::V1::Captain::PublicReservationsController < ActionController::API
  include ActionController::Cookies

  before_action :authenticate_reserva_token!

  # POST /public/api/v1/captain/public_reservations
  def create
    render json: { error: 'not_implemented' }, status: :not_implemented
  end

  # GET /public/api/v1/captain/public_reservations/:id/status
  def status
    render json: { error: 'not_implemented' }, status: :not_implemented
  end

  private

  def authenticate_reserva_token!
    expected = ENV.fetch('RESERVA_1001_API_TOKEN', nil)
    provided = request.headers['X-Reserva-Token']

    if expected.blank?
      Rails.logger.error('[PublicReservations] RESERVA_1001_API_TOKEN not configured')
      render json: { error: 'service_unavailable' }, status: :service_unavailable and return
    end

    if provided.blank? || !ActiveSupport::SecurityUtils.secure_compare(provided, expected)
      render json: { error: 'unauthorized' }, status: :unauthorized and return
    end
  end
end
```

- [ ] **Step 4: Rodar o spec novamente (deve passar nos testes de auth)**

```bash
bundle exec rspec spec/enterprise/controllers/public/api/v1/captain/public_reservations_controller_spec.rb 2>&1 | tail -20
```

Expected: 2 passed (`without token` → 401, `with invalid token` → 401).

Se falhar por problema de carregamento do arquivo, garantir que `enterprise/app/controllers/public/api/v1/captain/` é autoloaded (seguir o mesmo padrão do `inter_webhooks_controller.rb`).

- [ ] **Step 5: Commit**

```bash
git add config/routes.rb enterprise/app/controllers/public/api/v1/captain/public_reservations_controller.rb
git commit -m "feat: rota + controller esqueleto PublicReservations com token auth"
```

---

## Task B4: Teste RSpec — criar reserva + PIX (happy path)

**Files:**
- Modify: `chatwoot/spec/enterprise/controllers/public/api/v1/captain/public_reservations_controller_spec.rb`

- [ ] **Step 1: Adicionar contexto e teste de criação bem-sucedida**

Adicionar dentro do `describe 'POST ...'` bloco:

```ruby
    context 'with valid token and valid payload' do
      let(:unit) do
        create(
          :captain_unit,
          account: account,
          inbox: inbox,
          inter_client_id: 'fake-id',
          inter_client_secret: 'fake-secret',
          inter_pix_key: 'fake-key@test.com',
          inter_account_number: '1234567',
          inter_cert_content: 'FAKE-CERT',
          inter_key_content: 'FAKE-KEY'
        )
      end
      let(:account) { create(:account) }
      let(:inbox) { create(:inbox, account: account) }

      let(:valid_payload) do
        {
          chatwoot_unit_id: unit.id,
          category: 'Standard',
          stay_type: '3hrs',
          checkin_at: 2.hours.from_now.iso8601,
          customer: {
            name: 'Maria Teste',
            phone: '+5561999990000',
            cpf: '12345678909',
            email: 'maria@teste.com'
          },
          total_cents: 12_000,
          deposit_cents: 6_000,
          notes: 'Chegaremos às 15h'
        }
      end

      let(:fake_pix_charge) do
        double('PixCharge',
               id: 99,
               txid: 'test-txid-123',
               pix_copia_e_cola: '00020126...',
               status: 'active')
      end

      before do
        allow_any_instance_of(Captain::Inter::CobService).to receive(:call).and_return(fake_pix_charge)
      end

      it 'returns 201 with reservation and PIX payload' do
        post '/public/api/v1/captain/public_reservations',
             params: valid_payload.to_json,
             headers: {
               'Content-Type' => 'application/json',
               'X-Reserva-Token' => valid_token
             }

        expect(response).to have_http_status(:created)
        body = JSON.parse(response.body)
        expect(body['reservation_id']).to be_present
        expect(body['conversation_id']).to be_present
        expect(body['pix']['txid']).to eq('test-txid-123')
        expect(body['pix']['copia_e_cola']).to start_with('00020126')
      end

      it 'creates Contact, ContactInbox, Conversation and Reservation' do
        expect {
          post '/public/api/v1/captain/public_reservations',
               params: valid_payload.to_json,
               headers: {
                 'Content-Type' => 'application/json',
                 'X-Reserva-Token' => valid_token
               }
        }.to change(Contact, :count).by(1)
         .and change(Conversation, :count).by(1)
         .and change(Captain::Reservation, :count).by(1)
      end
    end
```

- [ ] **Step 2: Rodar (deve falhar — lógica ainda não existe)**

```bash
bundle exec rspec spec/enterprise/controllers/public/api/v1/captain/public_reservations_controller_spec.rb 2>&1 | tail -25
```

Expected: 2 novos FAIL (501 not_implemented em vez de 201). Os 2 de auth continuam passando.

- [ ] **Step 3: Commit**

```bash
git add spec/enterprise/controllers/public/api/v1/captain/public_reservations_controller_spec.rb
git commit -m "test: specs do happy path do PublicReservationsController (red)"
```

---

## Task B5: Implementar `create` — cria Contact, Conversation, Reservation, chama CobService

**Files:**
- Modify: `chatwoot/enterprise/app/controllers/public/api/v1/captain/public_reservations_controller.rb`

- [ ] **Step 1: Implementar o action `create`**

Substituir o método `create` do controller por:

```ruby
  def create
    unit = Captain::Unit.find_by(id: params[:chatwoot_unit_id])
    return render json: { error: 'unit_not_found' }, status: :not_found if unit.nil?
    return render json: { error: 'unit_has_no_inbox' }, status: :unprocessable_entity if unit.inbox_id.blank?
    return render json: { error: 'unit_missing_inter_credentials' }, status: :unprocessable_entity unless unit.inter_credentials_present?

    customer = params[:customer] || {}
    return render json: { error: 'customer_required' }, status: :unprocessable_entity if customer[:name].blank?

    account = unit.account
    inbox   = unit.inbox

    contact_inbox = ::ContactInboxWithContactBuilder.new(
      source_id: "reserva1001-#{SecureRandom.uuid}",
      inbox: inbox,
      contact_attributes: {
        name: customer[:name],
        phone_number: customer[:phone].presence,
        email: customer[:email].presence,
        additional_attributes: {
          cpf: customer[:cpf].presence,
          origem: 'reserva-1001'
        }.compact
      }
    ).perform

    conversation = ConversationBuilder.new(
      params: {
        additional_attributes: {
          source: 'reserva-1001',
          reserva_category: params[:category],
          reserva_stay_type: params[:stay_type],
          reserva_checkin_at: params[:checkin_at]
        }
      },
      contact_inbox: contact_inbox
    ).perform

    initial_note = <<~NOTE.strip
      🛎️ *Nova reserva via reserva.1001*
      Categoria: #{params[:category]}
      Permanência: #{params[:stay_type]}
      Check-in: #{params[:checkin_at]}
      Total: R$ #{format('%.2f', params[:total_cents].to_i / 100.0)}
      Entrada (PIX 50%): R$ #{format('%.2f', params[:deposit_cents].to_i / 100.0)}
      Observação: #{params[:notes].presence || '—'}
    NOTE

    Messages::MessageBuilder.new(
      nil,
      conversation,
      { content: initial_note, message_type: 'outgoing', private: true }
    ).perform

    reservation = Captain::Reservation.create!(
      account: account,
      inbox: inbox,
      contact: contact_inbox.contact,
      contact_inbox: contact_inbox,
      conversation: conversation,
      unit: unit,
      suite_identifier: "#{params[:category]} · #{params[:stay_type]}",
      check_in_at: params[:checkin_at],
      check_out_at: checkout_from(params[:checkin_at], params[:stay_type]),
      status: :draft,
      payment_status: 'pending',
      total_amount: (params[:total_cents].to_i / 100.0),
      metadata: {
        origem: 'reserva-1001',
        category: params[:category],
        stay_type: params[:stay_type],
        deposit_cents: params[:deposit_cents].to_i,
        notes: params[:notes]
      }
    )

    deposit_amount = (params[:deposit_cents].to_i / 100.0)
    charge = Captain::Inter::CobService.new(reservation, amount: deposit_amount).call
    reservation.update!(status: :pending_payment)

    render json: {
      reservation_id: reservation.id,
      conversation_id: conversation.id,
      pix: {
        txid: charge.txid,
        copia_e_cola: charge.pix_copia_e_cola,
        qrcode_base64: nil, # gerado no front via biblioteca qrcode (menos round-trip)
        expires_at: (Time.current + Captain::PixCharge::EXPIRATION_SECONDS.seconds).iso8601
      }
    }, status: :created
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.error("[PublicReservations] validation error: #{e.message}")
    render json: { error: 'validation_failed', details: e.record.errors.full_messages }, status: :unprocessable_entity
  rescue StandardError => e
    Rails.logger.error("[PublicReservations] unexpected error: #{e.class} - #{e.message}")
    render json: { error: 'internal_error', message: e.message }, status: :internal_server_error
  end

  private

  def checkout_from(checkin_iso, stay_type)
    checkin = Time.parse(checkin_iso.to_s)
    hours = case stay_type
            when '2hrs' then 2
            when '3hrs' then 3
            when '4hrs' then 4
            when 'Pernoite', 'pernoite' then 12
            when 'Diaria', 'diaria', 'Diária' then 24
            else 3
            end
    checkin + hours.hours
  end
```

(manter `authenticate_reserva_token!` privado abaixo)

- [ ] **Step 2: Rodar os specs**

```bash
bundle exec rspec spec/enterprise/controllers/public/api/v1/captain/public_reservations_controller_spec.rb 2>&1 | tail -30
```

Expected: 4 passing.

Se falhar por algum motivo (ex: factory não aceita inbox, `Captain::Unit` factory diferente), adaptar os testes/código e iterar até verde.

- [ ] **Step 3: Commit**

```bash
git add enterprise/app/controllers/public/api/v1/captain/public_reservations_controller.rb
git commit -m "feat: implementa POST /public_reservations (contact + conversa + reserva + pix)"
```

---

## Task B6: Teste + implementação do `status` (GET)

**Files:**
- Modify: `chatwoot/spec/enterprise/controllers/public/api/v1/captain/public_reservations_controller_spec.rb`
- Modify: `chatwoot/enterprise/app/controllers/public/api/v1/captain/public_reservations_controller.rb`

- [ ] **Step 1: Adicionar describe do GET /status**

Adicionar ao spec:

```ruby
  describe 'GET /public/api/v1/captain/public_reservations/:id/status' do
    let(:account) { create(:account) }
    let(:inbox)   { create(:inbox, account: account) }
    let(:contact) { create(:contact, account: account) }
    let(:contact_inbox) { create(:contact_inbox, inbox: inbox, contact: contact) }
    let(:unit) { create(:captain_unit, account: account, inbox: inbox) }
    let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox) }
    let(:reservation) do
      Captain::Reservation.create!(
        account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox,
        conversation: conversation, unit: unit, suite_identifier: 'Standard · 3hrs',
        check_in_at: 1.hour.from_now, check_out_at: 4.hours.from_now,
        status: :pending_payment, payment_status: 'pending', total_amount: 120.0
      )
    end

    it 'requires token' do
      get "/public/api/v1/captain/public_reservations/#{reservation.id}/status"
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns pending for unpaid reservation' do
      get "/public/api/v1/captain/public_reservations/#{reservation.id}/status",
          headers: { 'X-Reserva-Token' => valid_token }
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)['status']).to eq('pending')
    end

    it 'returns paid after payment_status flips' do
      reservation.update!(payment_status: 'paid')
      get "/public/api/v1/captain/public_reservations/#{reservation.id}/status",
          headers: { 'X-Reserva-Token' => valid_token }
      expect(JSON.parse(response.body)['status']).to eq('paid')
    end

    it 'returns 404 for unknown reservation' do
      get '/public/api/v1/captain/public_reservations/999999/status',
          headers: { 'X-Reserva-Token' => valid_token }
      expect(response).to have_http_status(:not_found)
    end
  end
```

- [ ] **Step 2: Implementar `status` no controller**

Substituir o método `status` do controller por:

```ruby
  def status
    reservation = Captain::Reservation.find_by(id: params[:id])
    return render json: { error: 'not_found' }, status: :not_found if reservation.nil?

    render json: {
      reservation_id: reservation.id,
      status: reservation.payment_status
    }
  end
```

- [ ] **Step 3: Rodar os specs**

```bash
bundle exec rspec spec/enterprise/controllers/public/api/v1/captain/public_reservations_controller_spec.rb 2>&1 | tail -30
```

Expected: 8 passing (4 do POST + 4 do GET).

- [ ] **Step 4: Commit**

```bash
git add spec/enterprise/controllers/public/api/v1/captain/public_reservations_controller_spec.rb enterprise/app/controllers/public/api/v1/captain/public_reservations_controller.rb
git commit -m "feat: implementa GET /public_reservations/:id/status"
```

---

## Task B7: Smoke test via curl contra o Chatwoot local

**Files:** nenhum arquivo novo.

- [ ] **Step 1: Garantir que o Chatwoot dev está rodando**

Se não estiver: abra outro terminal e rode `pnpm run dev` dentro de `chatwoot/`. Espere até ver "Listening on 0.0.0.0:3000".

- [ ] **Step 2: Curl — tentativa sem token (espera 401)**

```bash
curl -i -X POST http://localhost:3000/public/api/v1/captain/public_reservations \
  -H "Content-Type: application/json" \
  -d '{}'
```

Expected: `HTTP/1.1 401 Unauthorized`.

- [ ] **Step 3: Curl — tentativa com token válido e payload válido**

```bash
curl -i -X POST http://localhost:3000/public/api/v1/captain/public_reservations \
  -H "Content-Type: application/json" \
  -H "X-Reserva-Token: dev-token-change-in-prod" \
  -d '{
    "chatwoot_unit_id": 4,
    "category": "Standard",
    "stay_type": "3hrs",
    "checkin_at": "2026-04-14T23:00:00-03:00",
    "customer": {
      "name": "Teste Curl",
      "phone": "+5561999998877",
      "cpf": "12345678909",
      "email": "teste@curl.com"
    },
    "total_cents": 12000,
    "deposit_cents": 6000,
    "notes": "smoke test"
  }'
```

Expected: `HTTP/1.1 201 Created` com body JSON contendo `reservation_id`, `conversation_id`, `pix.txid`, `pix.copia_e_cola`.

**Se a Inter real responder com erro** (cert inválido no dev, endpoint bloqueado, etc): aceitar como "falhou por motivo externo à nossa lógica" e documentar. O RSpec já validou nossa lógica com mock.

- [ ] **Step 4: Curl — GET /status**

```bash
# Substituir <ID> pelo reservation_id retornado acima
curl -i http://localhost:3000/public/api/v1/captain/public_reservations/<ID>/status \
  -H "X-Reserva-Token: dev-token-change-in-prod"
```

Expected: `200 OK` com `{"reservation_id":...,"status":"pending"}`.

- [ ] **Step 5: Commit (se houve ajustes)**

Se os smoke tests exigiram correções no código, commit como `fix:`.

---

# PARTE C — Frontend (Fase 3)

## Task C1: Client HTTP do Chatwoot

**Files:**
- Modify: `reserva-1001/.env.local` e `.env.local.example`
- Create: `reserva-1001/src/lib/chatwootApi.ts`

- [ ] **Step 1: Garantir variáveis de ambiente**

Edit `reserva-1001/.env.local`, adicionar/completar:
```
VITE_CHATWOOT_API_URL=http://localhost:3000
VITE_CHATWOOT_API_TOKEN=dev-token-change-in-prod
```

Edit `.env.local.example` do mesmo jeito (com token em branco).

- [ ] **Step 2: Criar o client**

Create `reserva-1001/src/lib/chatwootApi.ts`:
```ts
const API_URL = import.meta.env.VITE_CHATWOOT_API_URL
const API_TOKEN = import.meta.env.VITE_CHATWOOT_API_TOKEN

if (!API_URL || !API_TOKEN) {
  console.warn('VITE_CHATWOOT_API_URL / VITE_CHATWOOT_API_TOKEN nao definidos')
}

export interface CreateReservationInput {
  chatwoot_unit_id: number
  category: string
  stay_type: string
  checkin_at: string // ISO
  customer: {
    name: string
    phone: string
    cpf: string
    email?: string
  }
  total_cents: number
  deposit_cents: number
  notes?: string
}

export interface CreateReservationResponse {
  reservation_id: number
  conversation_id: number
  pix: {
    txid: string
    copia_e_cola: string
    qrcode_base64: string | null
    expires_at: string
  }
}

export interface StatusResponse {
  reservation_id: number
  status: 'pending' | 'paid' | 'expired' | 'canceled'
}

async function request<T>(path: string, init: RequestInit = {}): Promise<T> {
  const res = await fetch(`${API_URL}${path}`, {
    ...init,
    headers: {
      'Content-Type': 'application/json',
      'X-Reserva-Token': API_TOKEN,
      ...(init.headers ?? {}),
    },
  })

  if (!res.ok) {
    const body = await res.text().catch(() => '')
    throw new Error(`Chatwoot API ${res.status}: ${body || res.statusText}`)
  }

  return (await res.json()) as T
}

export const chatwootApi = {
  createReservation(input: CreateReservationInput): Promise<CreateReservationResponse> {
    return request('/public/api/v1/captain/public_reservations', {
      method: 'POST',
      body: JSON.stringify(input),
    })
  },

  getStatus(id: number): Promise<StatusResponse> {
    return request(`/public/api/v1/captain/public_reservations/${id}/status`)
  },
}
```

- [ ] **Step 3: Typecheck + commit**

```bash
cd /Users/user/Dev/Produtos/Chatwoot-fazer-ai/fazer-ai-kanban/reserva-1001
pnpm typecheck
git add .env.local.example src/lib/chatwootApi.ts
git commit -m "feat: client http do endpoint publico do chatwoot"
```

---

## Task C2: Formatadores (BRL, CPF, telefone)

**Files:**
- Create: `reserva-1001/src/lib/formatters.ts`

- [ ] **Step 1: Criar**

```ts
export function formatBRL(cents: number): string {
  return (cents / 100).toLocaleString('pt-BR', {
    style: 'currency',
    currency: 'BRL',
  })
}

export function maskCPF(value: string): string {
  const digits = value.replace(/\D/g, '').slice(0, 11)
  return digits
    .replace(/(\d{3})(\d)/, '$1.$2')
    .replace(/(\d{3})(\d)/, '$1.$2')
    .replace(/(\d{3})(\d{1,2})$/, '$1-$2')
}

export function maskPhone(value: string): string {
  const digits = value.replace(/\D/g, '').slice(0, 11)
  if (digits.length <= 10) {
    return digits
      .replace(/(\d{2})(\d)/, '($1) $2')
      .replace(/(\d{4})(\d)/, '$1-$2')
  }
  return digits
    .replace(/(\d{2})(\d)/, '($1) $2')
    .replace(/(\d{5})(\d)/, '$1-$2')
}

export function onlyDigits(value: string): string {
  return value.replace(/\D/g, '')
}
```

- [ ] **Step 2: Commit**

```bash
git add src/lib/formatters.ts
git commit -m "feat: formatadores BRL, CPF e telefone"
```

---

## Task C3: Services do Supabase — unidades, preços, fotos, extras

**Files:**
- Create: `reserva-1001/src/services/catalogoService.ts`

- [ ] **Step 1: Criar**

```ts
import { supabase } from '@/lib/supabase'
import type { Database } from '@/types/database'

type Marca = Database['reserva_hotel']['Tables']['marcas']['Row']
type Unidade = Database['reserva_hotel']['Tables']['unidades']['Row']
type Preco = Database['reserva_hotel']['Tables']['precos']['Row']
type Foto = Database['reserva_hotel']['Tables']['fotos_categoria']['Row']
type Extra = Database['reserva_hotel']['Tables']['extras']['Row']

export const catalogoService = {
  async listMarcas(): Promise<Marca[]> {
    const { data, error } = await supabase
      .from('marcas')
      .select('*')
      .eq('ativa', true)
      .order('nome')
    if (error) throw new Error(error.message)
    return data ?? []
  },

  async listUnidades(marcaId: string): Promise<Unidade[]> {
    const { data, error } = await supabase
      .from('unidades')
      .select('*')
      .eq('id_marca', marcaId)
      .eq('ativa', true)
      .order('nome')
    if (error) throw new Error(error.message)
    return data ?? []
  },

  async findPreco(
    marcaId: string,
    categoria: string,
    permanencia: string,
    periodo = 'default'
  ): Promise<Preco | null> {
    const { data, error } = await supabase
      .from('precos')
      .select('*')
      .eq('id_marca', marcaId)
      .eq('categoria', categoria)
      .eq('permanencia', permanencia)
      .eq('periodo_semana', periodo)
      .eq('ativo', true)
      .maybeSingle()
    if (error) throw new Error(error.message)
    return data
  },

  async listFotos(unidadeId: string, categoria: string): Promise<Foto[]> {
    const { data, error } = await supabase
      .from('fotos_categoria')
      .select('*')
      .eq('id_unidade', unidadeId)
      .eq('categoria', categoria)
      .eq('ativa', true)
      .order('ordem')
    if (error) throw new Error(error.message)
    return data ?? []
  },

  async listExtras(marcaId: string): Promise<Extra[]> {
    const { data, error } = await supabase
      .from('extras')
      .select('*')
      .eq('id_marca', marcaId)
      .eq('ativo', true)
      .order('ordem')
    if (error) throw new Error(error.message)
    return data ?? []
  },
}
```

- [ ] **Step 2: Typecheck**

```bash
pnpm typecheck
```

- [ ] **Step 3: Commit**

```bash
git add src/services/catalogoService.ts
git commit -m "feat: catalogoService com queries de marcas/unidades/precos/fotos/extras"
```

---

## Task C4: Hook `useReservationForm` (estado consolidado)

**Files:**
- Create: `reserva-1001/src/hooks/useReservationForm.ts`

- [ ] **Step 1: Criar**

```ts
import { useEffect, useState, useCallback } from 'react'
import { catalogoService } from '@/services/catalogoService'
import type { Database } from '@/types/database'

type Marca = Database['reserva_hotel']['Tables']['marcas']['Row']
type Unidade = Database['reserva_hotel']['Tables']['unidades']['Row']
type Preco = Database['reserva_hotel']['Tables']['precos']['Row']
type Foto = Database['reserva_hotel']['Tables']['fotos_categoria']['Row']

export interface ReservationFormState {
  marcaId: string
  unidadeId: string
  permanencia: string
  categoria: string
  checkinAt: string // datetime-local format
  nome: string
  telefone: string
  cpf: string
  email: string
  observacao: string
}

const empty: ReservationFormState = {
  marcaId: '',
  unidadeId: '',
  permanencia: '',
  categoria: '',
  checkinAt: '',
  nome: '',
  telefone: '',
  cpf: '',
  email: '',
  observacao: '',
}

export function useReservationForm() {
  const [form, setForm] = useState<ReservationFormState>(empty)
  const [marcas, setMarcas] = useState<Marca[]>([])
  const [unidades, setUnidades] = useState<Unidade[]>([])
  const [preco, setPreco] = useState<Preco | null>(null)
  const [fotos, setFotos] = useState<Foto[]>([])
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)

  // Carregar marcas uma vez
  useEffect(() => {
    catalogoService
      .listMarcas()
      .then(setMarcas)
      .catch((err: Error) => setError(err.message))
  }, [])

  // Quando muda marca, buscar unidades
  useEffect(() => {
    if (!form.marcaId) {
      setUnidades([])
      return
    }
    catalogoService
      .listUnidades(form.marcaId)
      .then(setUnidades)
      .catch((err: Error) => setError(err.message))
  }, [form.marcaId])

  // Quando tem marca + categoria + permanência, buscar preço
  useEffect(() => {
    if (!form.marcaId || !form.categoria || !form.permanencia) {
      setPreco(null)
      return
    }
    catalogoService
      .findPreco(form.marcaId, form.categoria, form.permanencia)
      .then(setPreco)
      .catch((err: Error) => setError(err.message))
  }, [form.marcaId, form.categoria, form.permanencia])

  // Quando tem unidade + categoria, buscar fotos
  useEffect(() => {
    if (!form.unidadeId || !form.categoria) {
      setFotos([])
      return
    }
    catalogoService
      .listFotos(form.unidadeId, form.categoria)
      .then(setFotos)
      .catch((err: Error) => setError(err.message))
  }, [form.unidadeId, form.categoria])

  const update = useCallback(<K extends keyof ReservationFormState>(
    key: K,
    value: ReservationFormState[K]
  ) => {
    setForm((prev) => {
      const next = { ...prev, [key]: value }
      // Reset em cascata
      if (key === 'marcaId') {
        next.unidadeId = ''
        next.categoria = ''
        next.permanencia = ''
      }
      if (key === 'unidadeId') {
        next.categoria = ''
      }
      return next
    })
  }, [])

  const marcaSelecionada = marcas.find((m) => m.id === form.marcaId) ?? null
  const unidadeSelecionada = unidades.find((u) => u.id === form.unidadeId) ?? null

  const precoTotalCents = preco ? Math.round(Number(preco.valor) * 100) : 0
  const depositCents = Math.round(precoTotalCents / 2)

  const canSubmit =
    form.marcaId !== '' &&
    form.unidadeId !== '' &&
    form.categoria !== '' &&
    form.permanencia !== '' &&
    form.checkinAt !== '' &&
    form.nome.trim() !== '' &&
    form.telefone.replace(/\D/g, '').length >= 10 &&
    form.cpf.replace(/\D/g, '').length === 11 &&
    preco !== null

  return {
    form,
    update,
    marcas,
    unidades,
    marcaSelecionada,
    unidadeSelecionada,
    preco,
    precoTotalCents,
    depositCents,
    fotos,
    loading,
    setLoading,
    error,
    setError,
    canSubmit,
    reset: () => setForm(empty),
  }
}
```

- [ ] **Step 2: Typecheck e commit**

```bash
pnpm typecheck
git add src/hooks/useReservationForm.ts
git commit -m "feat: hook useReservationForm com estado em cascata"
```

---

## Task C5: Componente `StayDetailsStep` (form em cascata)

**Files:**
- Create: `reserva-1001/src/components/reservation/StayDetailsStep.tsx`

- [ ] **Step 1: Criar**

```tsx
import { SelectField } from '@/components/SelectField'
import { FormField } from '@/components/FormField'
import type { ReservationFormState } from '@/hooks/useReservationForm'
import type { Database } from '@/types/database'

type Marca = Database['reserva_hotel']['Tables']['marcas']['Row']
type Unidade = Database['reserva_hotel']['Tables']['unidades']['Row']

interface Props {
  form: ReservationFormState
  marcas: Marca[]
  unidades: Unidade[]
  onChange: <K extends keyof ReservationFormState>(k: K, v: ReservationFormState[K]) => void
}

export function StayDetailsStep({ form, marcas, unidades, onChange }: Props) {
  const marca = marcas.find((m) => m.id === form.marcaId) ?? null
  const unidade = unidades.find((u) => u.id === form.unidadeId) ?? null

  const categoriaOptions =
    unidade?.categorias_visiveis?.map((c) => ({ value: c, label: c })) ??
    marca?.categorias?.map((c) => ({ value: c, label: c })) ??
    []

  const permanenciaOptions =
    marca?.permanencias?.map((p) => ({ value: p, label: p })) ?? []

  return (
    <section className="space-y-6 rounded-2xl border border-champagne/20 bg-midnight/50 p-6 backdrop-blur">
      <h2 className="font-serif text-2xl text-champagne">Detalhes da estadia</h2>

      <SelectField
        label="Marca"
        required
        value={form.marcaId}
        onChange={(e) => onChange('marcaId', e.target.value)}
        options={marcas.map((m) => ({ value: m.id, label: m.nome }))}
      />

      <SelectField
        label="Unidade do Hotel"
        required
        disabled={!form.marcaId}
        value={form.unidadeId}
        onChange={(e) => onChange('unidadeId', e.target.value)}
        options={unidades.map((u) => ({ value: u.id, label: u.nome }))}
      />

      <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
        <SelectField
          label="Permanência"
          required
          disabled={!form.marcaId}
          value={form.permanencia}
          onChange={(e) => onChange('permanencia', e.target.value)}
          options={permanenciaOptions}
        />

        <SelectField
          label="Categoria da suíte"
          required
          disabled={!form.unidadeId}
          value={form.categoria}
          onChange={(e) => onChange('categoria', e.target.value)}
          options={categoriaOptions}
        />
      </div>

      <FormField
        label="Data e horário do check-in"
        required
        type="datetime-local"
        value={form.checkinAt}
        onChange={(e) => onChange('checkinAt', e.target.value)}
      />
    </section>
  )
}
```

- [ ] **Step 2: Typecheck + commit**

```bash
pnpm typecheck
git add src/components/reservation/StayDetailsStep.tsx
git commit -m "feat: StayDetailsStep com selects em cascata"
```

---

## Task C6: `ImageGallery` e `PriceSummary`

**Files:**
- Create: `reserva-1001/src/components/reservation/ImageGallery.tsx`
- Create: `reserva-1001/src/components/reservation/PriceSummary.tsx`

- [ ] **Step 1: ImageGallery**

Create `src/components/reservation/ImageGallery.tsx`:
```tsx
import type { Database } from '@/types/database'

type Foto = Database['reserva_hotel']['Tables']['fotos_categoria']['Row']

interface Props {
  fotos: Foto[]
}

export function ImageGallery({ fotos }: Props) {
  if (fotos.length === 0) return null

  return (
    <section className="grid grid-cols-1 md:grid-cols-2 gap-3">
      {fotos.map((foto) => (
        <div
          key={foto.id}
          className="aspect-video overflow-hidden rounded-xl border border-champagne/20"
        >
          <img
            src={foto.url_foto}
            alt={foto.alt ?? 'Foto da suíte'}
            className="h-full w-full object-cover transition duration-500 hover:scale-105"
          />
        </div>
      ))}
    </section>
  )
}
```

- [ ] **Step 2: PriceSummary**

Create `src/components/reservation/PriceSummary.tsx`:
```tsx
import { formatBRL } from '@/lib/formatters'

interface Props {
  totalCents: number
  depositCents: number
}

export function PriceSummary({ totalCents, depositCents }: Props) {
  if (totalCents === 0) return null
  const restante = totalCents - depositCents

  return (
    <section className="rounded-2xl border border-champagne/30 bg-midnight/60 p-6 backdrop-blur">
      <div className="flex items-baseline justify-between mb-3">
        <span className="text-slate text-sm uppercase tracking-widest">Preço estimado</span>
        <span className="font-serif text-3xl text-champagne">{formatBRL(totalCents)}</span>
      </div>
      <div className="flex items-baseline justify-between text-slate text-sm mb-2">
        <span>Pagar no check-in</span>
        <span>{formatBRL(restante)}</span>
      </div>
      <div className="mt-4 flex items-baseline justify-between rounded-xl border border-champagne/40 bg-champagne/10 px-4 py-3">
        <div>
          <div className="text-xs uppercase tracking-widest text-champagne">Entrada via PIX (50%)</div>
          <div className="text-slate text-xs">Necessário para confirmar</div>
        </div>
        <div className="font-serif text-3xl text-gradient-gold">{formatBRL(depositCents)}</div>
      </div>
    </section>
  )
}
```

- [ ] **Step 3: Typecheck + commit**

```bash
pnpm typecheck
git add src/components/reservation/ImageGallery.tsx src/components/reservation/PriceSummary.tsx
git commit -m "feat: ImageGallery + PriceSummary"
```

---

## Task C7: `CustomerForm`

**Files:**
- Create: `reserva-1001/src/components/reservation/CustomerForm.tsx`

- [ ] **Step 1: Criar**

```tsx
import { FormField } from '@/components/FormField'
import { maskCPF, maskPhone } from '@/lib/formatters'
import type { ReservationFormState } from '@/hooks/useReservationForm'

interface Props {
  form: ReservationFormState
  onChange: <K extends keyof ReservationFormState>(k: K, v: ReservationFormState[K]) => void
}

export function CustomerForm({ form, onChange }: Props) {
  return (
    <section className="space-y-4 rounded-2xl border border-champagne/20 bg-midnight/50 p-6 backdrop-blur">
      <h2 className="font-serif text-2xl text-champagne">Seus dados</h2>

      <FormField
        label="Nome completo"
        required
        placeholder="Como no documento"
        value={form.nome}
        onChange={(e) => onChange('nome', e.target.value)}
      />

      <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
        <FormField
          label="Telefone / WhatsApp"
          required
          placeholder="(99) 99999-9999"
          value={form.telefone}
          onChange={(e) => onChange('telefone', maskPhone(e.target.value))}
        />
        <FormField
          label="CPF"
          required
          placeholder="000.000.000-00"
          value={form.cpf}
          onChange={(e) => onChange('cpf', maskCPF(e.target.value))}
        />
      </div>

      <FormField
        label="E-mail"
        type="email"
        placeholder="seu@email.com"
        value={form.email}
        onChange={(e) => onChange('email', e.target.value)}
      />

      <div>
        <label className="font-sans text-xs uppercase tracking-widest text-champagne">
          Observação (opcional)
        </label>
        <textarea
          className="mt-2 w-full rounded-lg border border-champagne/30 bg-midnight/60 px-4 py-3 font-sans text-ivory placeholder:text-slate focus:border-champagne focus:outline-none"
          rows={3}
          placeholder="Alguma preferência especial?"
          value={form.observacao}
          onChange={(e) => onChange('observacao', e.target.value)}
        />
      </div>
    </section>
  )
}
```

- [ ] **Step 2: Typecheck + commit**

```bash
pnpm typecheck
git add src/components/reservation/CustomerForm.tsx
git commit -m "feat: CustomerForm com mascaras CPF e telefone"
```

---

## Task C8: `PixCheckout` com polling

**Files:**
- Create: `reserva-1001/src/components/checkout/PixCheckout.tsx`

Primeiro, instalar uma lib de QR code leve:

- [ ] **Step 1: Instalar qrcode.react**

```bash
cd /Users/user/Dev/Produtos/Chatwoot-fazer-ai/fazer-ai-kanban/reserva-1001
pnpm add qrcode.react
```

- [ ] **Step 2: Criar o componente**

```tsx
import { useEffect, useState } from 'react'
import { QRCodeSVG } from 'qrcode.react'
import { chatwootApi, type CreateReservationResponse } from '@/lib/chatwootApi'
import { Button } from '@/components/ui/button'
import { formatBRL } from '@/lib/formatters'

interface Props {
  reservation: CreateReservationResponse
  depositCents: number
  onPaid: () => void
  onCancel: () => void
}

export function PixCheckout({ reservation, depositCents, onPaid, onCancel }: Props) {
  const [copied, setCopied] = useState(false)
  const [statusMsg, setStatusMsg] = useState<string>('Aguardando pagamento...')

  useEffect(() => {
    let canceled = false
    const interval = setInterval(async () => {
      try {
        const s = await chatwootApi.getStatus(reservation.reservation_id)
        if (canceled) return
        if (s.status === 'paid') {
          setStatusMsg('Pagamento confirmado!')
          clearInterval(interval)
          onPaid()
        } else if (s.status === 'expired' || s.status === 'canceled') {
          setStatusMsg(`Reserva ${s.status}`)
          clearInterval(interval)
        }
      } catch (err) {
        console.error('Erro no polling:', err)
      }
    }, 3000)

    return () => {
      canceled = true
      clearInterval(interval)
    }
  }, [reservation.reservation_id, onPaid])

  const handleCopy = async () => {
    await navigator.clipboard.writeText(reservation.pix.copia_e_cola)
    setCopied(true)
    setTimeout(() => setCopied(false), 2000)
  }

  return (
    <section className="mx-auto max-w-md space-y-6 rounded-2xl border border-champagne/30 bg-midnight/60 p-8 backdrop-blur">
      <header className="text-center">
        <p className="text-xs uppercase tracking-[0.3em] text-rose-gold">Pagamento</p>
        <h2 className="mt-2 font-serif text-3xl text-gradient-gold">
          {formatBRL(depositCents)}
        </h2>
        <p className="mt-1 text-sm text-slate">{statusMsg}</p>
      </header>

      <div className="mx-auto flex w-fit items-center justify-center rounded-xl border border-champagne/40 bg-ivory p-4 glow-champagne">
        <QRCodeSVG value={reservation.pix.copia_e_cola} size={220} level="M" />
      </div>

      <div>
        <label className="text-xs uppercase tracking-widest text-champagne">
          Pix copia-e-cola
        </label>
        <div className="mt-2 flex items-stretch gap-2">
          <input
            readOnly
            value={reservation.pix.copia_e_cola}
            className="flex-1 truncate rounded-lg border border-champagne/30 bg-obsidian/60 px-3 py-2 text-xs text-ivory"
          />
          <Button variant="secondary" size="sm" onClick={handleCopy}>
            {copied ? 'Copiado!' : 'Copiar'}
          </Button>
        </div>
      </div>

      <p className="text-center text-xs text-slate">
        Expira em 1h. Após o pagamento, esta tela atualiza automaticamente.
      </p>

      <Button variant="ghost" size="sm" onClick={onCancel} className="w-full">
        Cancelar e voltar
      </Button>
    </section>
  )
}
```

- [ ] **Step 3: Typecheck + commit**

```bash
pnpm typecheck
git add src/components/checkout/PixCheckout.tsx package.json pnpm-lock.yaml
git commit -m "feat: PixCheckout com QR code e polling de status"
```

---

## Task C9: `SuccessScreen`

**Files:**
- Create: `reserva-1001/src/components/checkout/SuccessScreen.tsx`

- [ ] **Step 1: Criar**

```tsx
import { Button } from '@/components/ui/button'

interface Props {
  onRestart: () => void
}

export function SuccessScreen({ onRestart }: Props) {
  return (
    <section className="mx-auto max-w-md text-center space-y-6 rounded-2xl border border-emerald/40 bg-emerald/10 p-10 backdrop-blur">
      <div className="mx-auto flex h-20 w-20 items-center justify-center rounded-full bg-emerald text-obsidian text-4xl font-bold">
        ✓
      </div>

      <h2 className="font-serif text-3xl text-ivory">Reserva confirmada!</h2>

      <p className="text-slate">
        O pagamento caiu e sua reserva já está registrada.
        <br />
        Nossa atendente foi avisada e vai confirmar os próximos passos pelo WhatsApp.
      </p>

      <Button variant="primary" size="md" onClick={onRestart} className="w-full">
        Fazer outra reserva
      </Button>
    </section>
  )
}
```

- [ ] **Step 2: Commit**

```bash
git add src/components/checkout/SuccessScreen.tsx
git commit -m "feat: SuccessScreen apos pagamento confirmado"
```

---

## Task C10: `ReservationFlow` + novo `App.tsx`

**Files:**
- Create: `reserva-1001/src/components/reservation/ReservationFlow.tsx`
- Modify: `reserva-1001/src/App.tsx`

- [ ] **Step 1: ReservationFlow**

Create `src/components/reservation/ReservationFlow.tsx`:
```tsx
import { useState } from 'react'
import { useReservationForm } from '@/hooks/useReservationForm'
import { chatwootApi, type CreateReservationResponse } from '@/lib/chatwootApi'
import { onlyDigits } from '@/lib/formatters'
import { StayDetailsStep } from './StayDetailsStep'
import { ImageGallery } from './ImageGallery'
import { PriceSummary } from './PriceSummary'
import { CustomerForm } from './CustomerForm'
import { PixCheckout } from '@/components/checkout/PixCheckout'
import { SuccessScreen } from '@/components/checkout/SuccessScreen'
import { Button } from '@/components/ui/button'

type Phase = 'form' | 'checkout' | 'success'

export function ReservationFlow() {
  const {
    form,
    update,
    marcas,
    unidades,
    unidadeSelecionada,
    precoTotalCents,
    depositCents,
    fotos,
    canSubmit,
    reset,
  } = useReservationForm()

  const [phase, setPhase] = useState<Phase>('form')
  const [submitting, setSubmitting] = useState(false)
  const [submitError, setSubmitError] = useState<string | null>(null)
  const [reservation, setReservation] = useState<CreateReservationResponse | null>(null)

  async function handleSubmit() {
    setSubmitting(true)
    setSubmitError(null)
    try {
      if (unidadeSelecionada?.chatwoot_unit_id == null) {
        throw new Error('Unidade não está vinculada ao Chatwoot')
      }

      const res = await chatwootApi.createReservation({
        chatwoot_unit_id: Number(unidadeSelecionada.chatwoot_unit_id),
        category: form.categoria,
        stay_type: form.permanencia,
        checkin_at: new Date(form.checkinAt).toISOString(),
        customer: {
          name: form.nome,
          phone: onlyDigits(form.telefone),
          cpf: onlyDigits(form.cpf),
          email: form.email || undefined,
        },
        total_cents: precoTotalCents,
        deposit_cents: depositCents,
        notes: form.observacao || undefined,
      })

      setReservation(res)
      setPhase('checkout')
    } catch (err) {
      setSubmitError(err instanceof Error ? err.message : 'Erro desconhecido')
    } finally {
      setSubmitting(false)
    }
  }

  function restart() {
    reset()
    setReservation(null)
    setSubmitError(null)
    setPhase('form')
  }

  if (phase === 'success') {
    return <SuccessScreen onRestart={restart} />
  }

  if (phase === 'checkout' && reservation) {
    return (
      <PixCheckout
        reservation={reservation}
        depositCents={depositCents}
        onPaid={() => setPhase('success')}
        onCancel={restart}
      />
    )
  }

  return (
    <div className="mx-auto w-full max-w-2xl space-y-6">
      <StayDetailsStep
        form={form}
        marcas={marcas}
        unidades={unidades}
        onChange={update}
      />

      <ImageGallery fotos={fotos} />

      <PriceSummary totalCents={precoTotalCents} depositCents={depositCents} />

      <CustomerForm form={form} onChange={update} />

      {submitError && (
        <div className="rounded-xl border border-ruby/40 bg-ruby/10 p-4 text-ivory">
          {submitError}
        </div>
      )}

      <Button
        variant="primary"
        size="lg"
        className="w-full"
        disabled={!canSubmit || submitting}
        onClick={handleSubmit}
      >
        {submitting ? 'Gerando PIX...' : 'Confirmar e pagar reserva'}
      </Button>
    </div>
  )
}
```

- [ ] **Step 2: Reescrever App.tsx**

Replace `src/App.tsx` com:
```tsx
import { ReservationFlow } from '@/components/reservation/ReservationFlow'

export default function App() {
  return (
    <main className="min-h-screen flex flex-col items-center px-6 py-12">
      <header className="text-center mb-10">
        <p className="font-sans text-sm uppercase tracking-[0.3em] text-rose-gold mb-4">
          Experiência exclusiva
        </p>
        <h1 className="font-serif text-5xl md:text-6xl text-gradient-gold mb-3">
          Reserva Rede 1001
        </h1>
        <p className="font-sans text-slate text-lg">
          Escolha, confirme e receba seu PIX na hora.
        </p>
      </header>

      <ReservationFlow />

      <footer className="mt-16 text-slate text-xs uppercase tracking-widest">
        © 2026 Reserva Rede 1001 · Experiência Exclusiva
      </footer>
    </main>
  )
}
```

- [ ] **Step 3: Ajustar o smoke test (que testava as marcas no App) pra simplesmente verificar o título**

Edit `src/__tests__/App.test.tsx` — deixar apenas o primeiro teste (de título) e remover os outros 2 que dependiam de App ler marcas diretamente (agora o ReservationFlow é quem lê):

```tsx
import { render, screen } from '@testing-library/react'
import { describe, it, expect } from 'vitest'
import App from '@/App'

// Mock do hook para não precisar de Supabase nos testes
vi.mock('@/hooks/useReservationForm', () => ({
  useReservationForm: () => ({
    form: {
      marcaId: '',
      unidadeId: '',
      permanencia: '',
      categoria: '',
      checkinAt: '',
      nome: '',
      telefone: '',
      cpf: '',
      email: '',
      observacao: '',
    },
    update: vi.fn(),
    marcas: [],
    unidades: [],
    marcaSelecionada: null,
    unidadeSelecionada: null,
    preco: null,
    precoTotalCents: 0,
    depositCents: 0,
    fotos: [],
    loading: false,
    setLoading: vi.fn(),
    error: null,
    setError: vi.fn(),
    canSubmit: false,
    reset: vi.fn(),
  }),
}))

describe('App', () => {
  it('renderiza o titulo premium', () => {
    render(<App />)
    expect(screen.getByRole('heading', { name: /reserva rede 1001/i })).toBeInTheDocument()
  })

  it('renderiza o botao de confirmar', () => {
    render(<App />)
    expect(screen.getByRole('button', { name: /confirmar e pagar reserva/i })).toBeInTheDocument()
  })
})
```

Adicione também no topo do arquivo de setup `vi` import se não houver: `import { vi } from 'vitest'`. E remova o antigo mock de `@/lib/supabase` do `src/__tests__/setup.ts` — agora não precisa mais porque mockamos o hook:

Edit `src/__tests__/setup.ts`:
```ts
import '@testing-library/jest-dom/vitest'
import { cleanup } from '@testing-library/react'
import { afterEach } from 'vitest'

afterEach(() => {
  cleanup()
})
```

- [ ] **Step 4: Rodar tudo**

```bash
pnpm typecheck
pnpm test
pnpm build
```

Todos devem passar. Se algum teste reclamar de `vi is not defined`, adicione `import { vi } from 'vitest'` no topo do arquivo.

- [ ] **Step 5: Commit**

```bash
git add src/components/reservation/ReservationFlow.tsx src/App.tsx src/__tests__/App.test.tsx src/__tests__/setup.ts
git commit -m "feat: ReservationFlow orquestrando form + checkout + sucesso"
```

---

## Task C11: Teste ponta-a-ponta local (manual)

- [ ] **Step 1: Chatwoot rodando em `localhost:3000` com o token configurado**

- [ ] **Step 2: Rodar o reserva-1001**

```bash
cd /Users/user/Dev/Produtos/Chatwoot-fazer-ai/fazer-ai-kanban/reserva-1001
pnpm dev
```

Abra `http://localhost:5180/`.

- [ ] **Step 3: Fluxo manual**

1. Selecionar Marca: "Hotel 1001 Noites"
2. Selecionar Unidade: "Hotel 1001 Águas Lindas"
3. Selecionar Permanência: "3hrs"
4. Selecionar Categoria: "Standard"
5. Escolher data/hora futura
6. Ver fotos + preço total R$ 120 + PIX 50% R$ 60
7. Preencher nome, telefone, CPF, email
8. Clicar "Confirmar e pagar reserva"
9. **Esperado:** aparece a tela de checkout com QR code e copia-e-cola
10. Abrir o Chatwoot em outra aba: deve ter uma nova conversa no inbox 2 com uma nota interna descrevendo a reserva e a mensagem de aguardando pagamento
11. Se tiver ambiente Inter real: pagar o PIX. A página deve detectar via polling (3s) e mostrar a tela de sucesso. No Chatwoot, a mensagem "✅ Pagamento confirmado!" aparece na conversa.

**Se o PIX real falhar** (cert, endpoint): validar pelo menos que a tela de checkout renderizou com os dados mockados do que o backend devolveu. Flag pra o user: "Inter real precisa ser testada com credenciais de produção ou sandbox".

- [ ] **Step 4: Documentar o que funcionou e o que não**

Se tudo OK: tag mental "Fase 2+3 done".
Se algo falhou: criar tasks de correção e iterar.

---

## Critérios de conclusão da Fase 2+3

**Backend:**
- [ ] `RESERVA_1001_API_TOKEN` documentado no `.env.example`
- [ ] 8 specs RSpec passando (auth + create + status)
- [ ] Smoke test via curl retorna 201 com PIX

**Frontend:**
- [ ] `pnpm typecheck`, `pnpm lint`, `pnpm test`, `pnpm build` todos passam
- [ ] Form em cascata funcional (marca→unidade→permanência→categoria→data)
- [ ] Preço resolvido a partir do Supabase
- [ ] Fotos da categoria exibidas
- [ ] Submit bate no Chatwoot e retorna PIX
- [ ] Checkout mostra QR code + copia-e-cola + polling
- [ ] Tela de sucesso quando `status=paid`

**Integração:**
- [ ] Nova conversa criada no Chatwoot ao submeter
- [ ] Nota interna com detalhes da reserva aparece na conversa
- [ ] Após pagamento real (ou mock via SQL update), tela de sucesso aparece
- [ ] Mensagem "✅ Pagamento confirmado!" chega na conversa via `ConfirmationService`

---

## Próximas fases

- **Fase 4 — Admin**: CRUD no reserva-1001 pra cadastrar unidades/categorias/preços/fotos com Supabase Auth
- **Fase 5 — Polish visual**: animações, carrossel de fotos, hero, skeletons, confetti no sucesso
- **Fase 6 — Deploy**: Vercel + subdomínio + testes de produção
