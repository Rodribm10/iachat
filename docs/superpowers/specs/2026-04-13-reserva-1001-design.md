# Reserva Rede 1001 — Design

**Data:** 2026-04-13
**Autor:** Rodrigo Borba Machado (com assistência do Claude)
**Status:** Aprovado para planejamento

---

## 1. Contexto e objetivo

O Grupo Nova opera 4 marcas de hotéis/motéis em Brasília e Natal: **Hotel 1001 Noites**, **1001 Noites Prime**, **1001 Noites Express** e **Dolce Amore**. Hoje a reserva é feita pela atendente via WhatsApp, que gera um PIX usando a ferramenta `Captain::Tools::GeneratePix` dentro do Chatwoot fazer.ai. Essa ferramenta pode falhar (erro de API, mTLS, autenticação), e quando falha não há fallback automatizado.

**Objetivo:** criar uma página pública de reserva onde o próprio cliente:
1. Escolhe marca → unidade → permanência → categoria de suíte → data/hora de check-in
2. Vê fotos da categoria e o preço total
3. Preenche dados pessoais (nome, telefone, CPF, e-mail)
4. Paga 50% de entrada via PIX (QR code + copia-e-cola) direto na página
5. Ao confirmar o pagamento, uma mensagem automática aparece na conversa do WhatsApp da atendente no Chatwoot

É fallback pro fluxo manual e também canal direto de auto-atendimento.

**Escopo EXCLUÍDO:**
- Disponibilidade em tempo real (é catálogo fixo — atendente resolve conflitos no check-in)
- Integração com PMS externo
- Login de cliente / histórico de reservas do cliente
- Reserva de suíte específica (sempre por categoria)
- Segunda metade do pagamento online (50% restantes ficam para o check-in)

---

## 2. Decisões-chave

| Decisão | Escolha | Motivo |
|---|---|---|
| App separado do Chatwoot | ✅ Sim | Stack diferente (React vs Rails/Vue 2), deploy diferente, Chatwoot é dashboard interno ruim para página de conversão |
| Stack | Vite + React 19 + TS | Mantém o POC existente, evita overkill do Next.js para app de checkout |
| UI | Tailwind v4 + shadcn/ui + Radix | Mantém base do POC, adiciona shadcn oficial |
| Animação | framer-motion (já tem) + anime.js (adicionar) | Pedido do usuário |
| Banco | Supabase Postgres + Auth + Storage | Usuário já usa Supabase |
| Deploy | Vercel | Grátis, deploy em 30s |
| Geração de PIX | **Chatwoot API** (novo endpoint) | Reusa `Captain::Inter::CobService`, `PixCharge`, webhook Inter e `ConfirmationService` — zero duplicação, auto-mensagem no WhatsApp de graça |
| Detecção de pagamento | Webhook Inter existente (`/api/v1/captain/webhooks/inter_pix`) | Já funciona hoje; novo app só consulta status |
| Repositório | `fazer-ai-kanban/reserva-1001/` (irmão do `chatwoot/`) | Separado mas próximo |

---

## 3. Identidade visual — paleta premium

Inspiração: hotelaria de luxo boutique, tema árabe noturno de 1001 Noites, sensual sem ser brega.

| Token | Hex | Uso |
|---|---|---|
| `obsidian` | `#0B0D12` | Fundo principal |
| `midnight` | `#0F1A2E` | Superfícies elevadas (cards, modais) |
| `champagne` | `#C9A961` | Ação primária, destaques de luxo, botão "Confirmar e Pagar" |
| `rose-gold` | `#E8B4A0` | Ação secundária, acentos sensuais, labels de carinho |
| `ivory` | `#F5F1E8` | Texto principal sobre fundos escuros |
| `slate` | `#6B7280` | Texto secundário, placeholders |
| `emerald` | `#10B981` | Estado de sucesso (pagamento confirmado) |
| `ruby` | `#E11D48` | Estado de erro, validações |

**Tipografia:** manter **Inter** (já no POC) para UI. Adicionar **Fraunces** (serif display) para hero e títulos — dá contraste editorial/luxo.

**Gradientes:** `obsidian → midnight` no fundo, `champagne → rose-gold` em CTAs.

---

## 4. Arquitetura de alto nível

```
┌────────────────────────┐       ┌────────────────────────┐
│   reserva-1001         │       │   Chatwoot (Rails)     │
│   React + Vite         │──API─▶│                        │
│   Supabase             │       │   Novo controller:     │
│   Vercel               │       │   PublicReservations   │
│                        │       │                        │
│   • Página pública     │       │   Reusa existente:     │
│   • Admin              │       │   • Captain::Inter::   │
│   • Checkout PIX       │       │     CobService         │
└─────────┬──────────────┘       │   • PixCharge          │
          │                      │   • ConfirmationSvc    │
          ▼                      │   • Webhook Inter      │
   ┌─────────────┐               │   • Auto-msg WhatsApp  │
   │  Supabase   │               └────────────────────────┘
   │  Postgres   │                           ▲
   │  Auth       │                           │
   │  Storage    │                      webhook
   └─────────────┘                           │
                                     ┌───────┴──────┐
                                     │ Banco Inter  │
                                     └──────────────┘
```

**Separação de responsabilidades:**

| Sistema | É dono de |
|---|---|
| **reserva-1001** | UX pública, UX admin, cadastro (marcas/unidades/categorias/preços/fotos/extras), formulário de reserva, tela de checkout, polling de status |
| **Chatwoot** | Contato, conversa, inbox WhatsApp, geração de PIX via Inter, PixCharge, detecção de pagamento, mensagem automática na conversa da atendente |

O novo app **não** duplica nada do Chatwoot — ele consome a API.

---

## 5. Modelo de dados (Supabase)

Reformulação sobre o schema do POC, corrigindo problemas e adicionando o que falta.

```sql
-- Marcas (4 fixas inicialmente)
brands (
  id            bigserial primary key,
  name          text not null,
  slug          text not null unique,
  logo_url      text,
  primary_color text,
  created_at    timestamptz default now()
)

-- Unidades físicas de cada marca
hotel_units (
  id                bigserial primary key,
  brand_id          bigint references brands(id) on delete cascade,
  name              text not null,
  slug              text not null,
  chatwoot_unit_id  bigint not null, -- FK lógica pro Captain::Unit do Chatwoot
  active            boolean default true,
  created_at        timestamptz default now(),
  unique (brand_id, slug)
)

-- Categorias de suíte (antes era JSON em hotel_units)
suite_categories (
  id          bigserial primary key,
  unit_id     bigint references hotel_units(id) on delete cascade,
  name        text not null,
  description text,
  sort_order  int default 0,
  active      boolean default true,
  created_at  timestamptz default now()
)

-- Fotos por categoria (antes era JSON)
suite_images (
  id            bigserial primary key,
  category_id   bigint references suite_categories(id) on delete cascade,
  storage_path  text not null,  -- path no Supabase Storage
  alt           text,
  sort_order    int default 0,
  created_at    timestamptz default now()
)

-- Preços por categoria + faixa de dia + tipo de permanência (em centavos)
pricing (
  id              bigserial primary key,
  category_id     bigint references suite_categories(id) on delete cascade,
  day_range       text not null, -- 'weekday' | 'weekend' (enum)
  stay_type       text not null, -- '2hrs' | '3hrs' | '4hrs' | 'pernoite' | 'diaria'
  price_cents     int not null check (price_cents >= 0),
  created_at      timestamptz default now(),
  unique (category_id, day_range, stay_type)
)

-- Extras (antes era localStorage)
extras (
  id            bigserial primary key,
  brand_id      bigint references brands(id) on delete cascade,
  title         text not null,
  description   text,
  price_cents   int not null,
  image_url     text,
  active        boolean default true,
  sort_order    int default 0,
  created_at    timestamptz default now()
)

-- Reservas (NOVA — hoje só vai pro N8N, perdendo histórico)
reservations (
  id                       bigserial primary key,
  brand_id                 bigint references brands(id),
  unit_id                  bigint references hotel_units(id),
  category_id              bigint references suite_categories(id),
  stay_type                text not null,
  checkin_at               timestamptz not null,
  customer_name            text not null,
  customer_phone           text not null,
  customer_cpf             text not null,
  customer_email           text,
  notes                    text,
  total_cents              int not null,
  deposit_cents            int not null,
  chatwoot_contact_id      bigint,
  chatwoot_conversation_id bigint,
  chatwoot_pix_charge_id   bigint,
  pix_txid                 text,
  status                   text not null default 'pending', -- pending|paid|expired|canceled
  created_at               timestamptz default now(),
  paid_at                  timestamptz
)

-- Reserva ↔ extras escolhidos
reservation_extras (
  reservation_id  bigint references reservations(id) on delete cascade,
  extra_id        bigint references extras(id),
  price_cents     int not null, -- snapshot do preço no momento
  primary key (reservation_id, extra_id)
)
```

**RLS (Row Level Security):**
- Leitura pública: `brands`, `hotel_units` (active), `suite_categories` (active), `suite_images`, `pricing`, `extras` (active)
- Escrita: só pro role `admin` (Supabase Auth)
- `reservations`: leitura só da própria (via service_role no backend Vite)

**Bug corrigido do POC:**
- `day_range` hoje checa `dayOfWeek >= 1 && <= 3`, mas domingo é 0, fazendo domingo cair em "quinta a domingo" errado.
- Novo schema usa enum `'weekday' | 'weekend'` e a função de mapeamento é:
  ```ts
  // weekday: segunda(1) a quinta(4)
  // weekend: sexta(5), sábado(6), domingo(0)
  const isWeekend = (d: Date) => [0, 5, 6].includes(d.getDay())
  ```

---

## 6. Integração Chatwoot — endpoint novo

Único código novo no Chatwoot: um controller público autenticado por token.

### Arquivo novo
`enterprise/app/controllers/public/api/v1/captain/public_reservations_controller.rb`

### Rotas
```ruby
# config/routes.rb — dentro do enterprise namespace
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

### Autenticação
Token opaco gerado como variável de ambiente no Chatwoot (`RESERVA_1001_API_TOKEN`), validado por `before_action`. **Não é login de agente.**

### POST `/public/api/v1/captain/public_reservations`

**Request:**
```json
{
  "chatwoot_unit_id": 42,
  "category": "Spa-Hidromassagem",
  "stay_type": "3hrs",
  "checkin_at": "2026-04-14T23:57:00-03:00",
  "customer": {
    "name": "João da Silva",
    "phone": "+5561999998888",
    "cpf": "123.456.789-00",
    "email": "joao@exemplo.com"
  },
  "total_cents": 17000,
  "deposit_cents": 8500,
  "notes": "Chegaremos com 15 min de atraso"
}
```

**Fluxo interno do controller:**
1. Valida token
2. Carrega `Captain::Unit` por `chatwoot_unit_id`
3. Cria ou atualiza `Contact` no account da unit (match por CPF ou telefone)
4. Cria `Conversation` no inbox WhatsApp da unit com nota inicial da reserva
5. Cria `Captain::Reservation` (status pending)
6. Chama `Captain::Inter::CobService#call` com CPF, valor do depósito, PIX key da unit
7. Cria `Captain::PixCharge` vinculada à reservation
8. Retorna payload de checkout

**Response:**
```json
{
  "reservation_id": 9931,
  "conversation_id": 4421,
  "pix": {
    "txid": "a1b2c3d4e5...",
    "copia_e_cola": "00020126...",
    "qrcode_base64": "data:image/png;base64,iVBORw0...",
    "expires_at": "2026-04-14T00:57:00-03:00"
  }
}
```

### GET `/public/api/v1/captain/public_reservations/:id/status`

Retorna `{ "status": "pending" | "paid" | "expired" }`. Usado pelo front pra polling a cada 3s na tela de checkout.

### Pagamento
- Cliente paga no app do banco dele
- Inter bate webhook no endpoint **que já existe**: `/api/v1/captain/webhooks/inter_pix`
- `Captain::Payments::ConfirmationService` já marca a reservation como `paid`, adiciona labels `pagamento_confirmado` + `reserva_feita`, e **já dispara a mensagem automática "✅ Pagamento confirmado!" na conversa da atendente**

**Zero código novo pro pagamento.** O controller novo só orquestra a criação.

---

## 7. Fluxo do cliente (UX)

```
1. Landing pública
   ↓
2. Hero section ("Reserve a experiência que você merece")
   ↓
3. Formulário em cascata:
   Marca → Unidade → Permanência → Categoria → Data/Hora
   ↓
4. Preview: fotos da categoria (carrossel + lightbox)
             + preço total destacado
             + valor do PIX (50%) destacado
             + extras opcionais (se tiver)
   ↓
5. Dados pessoais: nome, telefone, CPF, email, observação
   ↓
6. [Confirmar e Pagar Reserva]
   ↓
7. Loading (skeleton enquanto chama API)
   ↓
8. Tela de checkout:
   - QR code (com glow animado champagne)
   - Copia-e-cola (botão de copy com feedback)
   - Timer regressivo ("Válido por 59:48")
   - Polling de status a cada 3s
   ↓
9. Cliente paga no banco
   ↓
10. Status muda pra "paid" → animação de sucesso:
    - Confetti champagne + rose-gold
    - Check desenhado com anime.js (stroke draw)
    - Mensagem: "Reserva confirmada! Sua atendente já foi avisada."
   ↓
11. Botão "Voltar ao início" / link do WhatsApp da atendente
```

---

## 8. Página admin

`/admin` — Supabase Auth (email + senha).

**Abas:**
- **Marcas** — CRUD simples (nome, logo, cor primária)
- **Unidades** — CRUD vinculado a marca, com `chatwoot_unit_id` (dropdown buscando via API do Chatwoot)
- **Categorias** — CRUD vinculado a unidade, ordem, ativo/inativo
- **Fotos** — upload drag-and-drop pro Supabase Storage, preview, reorder
- **Preços** — tabela editável (categoria × day_range × stay_type)
- **Extras** — CRUD vinculado a marca
- **Reservas** — só leitura, lista com filtros (status, data, unidade), detalhe com link pra conversa no Chatwoot

---

## 9. Refatoração do POC — o que herdar, o que refazer

### Herdar (copiar direto ou com ajustes mínimos)
- `components/FormField.tsx`, `components/SelectField.tsx`
- `components/ui/*` (shadcn base)
- Estrutura de seleção em cascata
- `index.css` (design tokens base)
- `vite.config.ts`, `tsconfig.json`

### Refazer
- `App.tsx` (730 linhas, monolito) → quebrar em:
  - `pages/ReservationPage.tsx`
  - `components/reservation/HeroSection.tsx`
  - `components/reservation/ReservationForm.tsx`
  - `components/reservation/ImageCarousel.tsx`
  - `components/reservation/PriceSummary.tsx`
  - `components/reservation/ExtrasGrid.tsx`
  - `components/reservation/CustomerForm.tsx`
  - `components/checkout/PixCheckout.tsx`
  - `components/checkout/SuccessScreen.tsx`
  - `hooks/useReservationForm.ts` (consolida os 14+ useState)
- `components/AdminPage.tsx` (881 linhas) → uma aba por arquivo em `pages/admin/*`, com `AuthGate`
- `services/apiService.ts` → novo `services/chatwootApi.ts` que fala com o controller novo
- `services/*.ts` (brand/unit/pricing/suite) → regenerar após novo schema
- `supabaseClient.ts` → mover chaves pra `.env.local`, usar `import.meta.env.VITE_SUPABASE_*`
- `index.html` → remover `importmap` do `esm.sh`, Vite bundla tudo
- `types.ts` → regenerar via `supabase gen types typescript`

### Bug pra corrigir
- Lógica de `day_range` (domingo no ramo errado) — ver seção 5

---

## 10. Melhorias visuais (animações + polish)

1. **Hero section** — fundo com parallax suave, gradiente `obsidian → midnight`, título em Fraunces serif com reveal escalonado (framer-motion `staggerChildren`)
2. **Stagger entrance** nas opções de categoria/unidade quando muda a marca
3. **Carrossel de fotos** — swipe horizontal, indicadores, clique pra lightbox em tela cheia
4. **Pulse animation** no preço total quando recalcula (anime.js `scale: [1, 1.08, 1]`)
5. **QR code com glow** — borda animada pulsando champagne (anime.js `keyframes`)
6. **Skeleton screens** durante fetch inicial e submissão
7. **Tela de sucesso** — confetti + check SVG desenhado com anime.js `stroke-dashoffset` (efeito de "desenhar" o check)
8. **Flip cards** nos extras (CSS `rotateY` on hover)
9. **Transições entre etapas** — `AnimatePresence` do framer-motion, slide + fade
10. **Tipografia editorial** — Fraunces nos títulos, Inter no resto, kerning generoso
11. **Microinterações** em botões — hover com `scale: 1.02` + glow champagne sutil
12. **Dark glassmorphism** nos cards de categoria (backdrop-blur sobre fundo escuro)

---

## 11. Plano de entrega em fases

| Fase | Escopo | Critério de pronto |
|---|---|---|
| **1. Fundação** | Novo projeto Vite limpo em `reserva-1001/`, migração do POC, Supabase novo schema aplicado, Tailwind v4 com paleta premium, `.env` configurado, remover `importmap` do HTML | `pnpm dev` roda, Tailwind tokens ativos, schema no Supabase |
| **2. Backend Chatwoot** | Controller `PublicReservationsController` com 2 endpoints + token auth + testes RSpec de integração | POST retorna PIX real, GET retorna status |
| **3. Fluxo público core** | Refatoração do App em componentes, hook `useReservationForm`, integração com API nova, checkout com polling, tela de sucesso | Cliente completa reserva end-to-end em ambiente de teste |
| **4. Admin** | Abas separadas, Supabase Auth, upload de fotos pro Storage, CRUD de todas entidades | Admin cadastra marca→unidade→categoria→fotos→preço |
| **5. Polish visual** | Hero, carrossel, animações (framer-motion + anime.js), skeletons, tipografia, microinterações | Revisão visual aprovada |
| **6. Deploy + QA** | Vercel com subdomínio, teste ponta-a-ponta com unidade real do Chatwoot, ajustes finais | Reserva real paga, mensagem cai na conversa da atendente |

---

## 12. Riscos e mitigações

| Risco | Mitigação |
|---|---|
| mTLS Inter falhar no controller novo | Controller reusa `Captain::Inter::CobService` — se falhar pra atendente, falha aqui também. Mesmo comportamento, mesmo suporte |
| Webhook Inter bate antes do front terminar de criar a reservation no Supabase | Chatwoot é a fonte de verdade da reserva e do PIX. Supabase só cacheia o ID pra tela do front. Ordem: chama Chatwoot → salva IDs no Supabase |
| Cliente sai da tela de checkout antes de pagar | Webhook Inter ainda dispara, reserva é marcada como paga no Chatwoot. Front perde a tela de sucesso mas a atendente recebe o aviso e entra em contato |
| Admin sem autenticação hoje (POC) | Fase 4 adiciona Supabase Auth obrigatório |
| Chave anon do Supabase exposta no repo do POC | Rotacionar antes do deploy, mover pra `.env` |
| Domingo precificado errado | Corrigido no novo schema (seção 5) |

---

## 13. Itens fora de escopo (V2)

- Segunda metade do pagamento online
- Disponibilidade em tempo real (bater PMS)
- Login de cliente / área logada
- Remarcação / cancelamento online
- E-mail transacional (confirmação)
- SMS de confirmação
- Google Analytics / tracking de conversão
- Multi-idioma (PT-BR apenas)
- App mobile nativo

---

## 14. Glossário

- **PIX Copia-e-cola**: string que o cliente cola no app do banco para pagar
- **txid**: ID único de transação PIX na Inter
- **PixCharge**: modelo no Chatwoot que rastreia uma cobrança PIX
- **Captain::Unit**: modelo no Chatwoot que representa uma unidade do hotel, com credenciais Inter próprias
- **Day range**: se o dia do check-in é dia de semana ou fim de semana, afeta preço
- **Stay type**: tipo de permanência (2hrs, 3hrs, 4hrs, pernoite, diária)
