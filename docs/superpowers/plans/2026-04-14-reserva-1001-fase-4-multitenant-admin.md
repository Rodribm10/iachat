# Reserva Rede 1001 — Fase 4: Multi-tenant SaaS + Admin

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task.

**Goal:** Transformar o `reserva-1001` num **produto SaaS multi-tenant**. Cada cliente (hotel/motel/rede) tem seu próprio subdomínio (`prime.reserva.app`, `motelxyz.reserva.app`), sua própria identidade visual (nome, cores, logo, fontes), seus próprios dados (marcas, unidades, preços, fotos, reservas) e seu próprio painel admin. Zero hardcode de "Rede 1001" — a página vira genérica e configurável.

**Architecture:**
- Subdomínio → tenant slug → carrega `app_config` e todas as queries scoped por `tenant_id`
- Supabase Auth pro admin, com `tenant_id` no user_metadata
- RLS policies filtram automaticamente por tenant
- Dev: `localhost:5180` usa `VITE_DEFAULT_TENANT_SLUG` (fallback)
- Prod: Vercel com wildcard domain `*.reserva.fazer.ai`

**Tech Stack:** Supabase (Postgres + Auth + Storage + RLS) · React 19 + Vite · TypeScript · Tailwind v4 CSS variables · Google Fonts dinâmico · Vercel

**Spec:** `docs/superpowers/specs/2026-04-13-reserva-1001-design.md`
**Fases anteriores:** Fase 1-3.5 completas.

---

## Escopo desta fase (o que entra)

1. **Multi-tenancy**: tabelas novas `tenants` + `app_config`, coluna `tenant_id` em tudo, backfill, RLS
2. **Identidade visual editável**: nome da rede, título, subtítulo, tagline, footer, logo, favicon, cor primária, cor secundária, cor de fundo, fonte display, fonte corpo
3. **Auth**: Supabase Auth (email + senha), seed do primeiro admin
4. **Frontend dinâmico**: resolve subdomínio, carrega config, injeta CSS variables + Google Fonts, substitui strings hardcoded
5. **Admin CRUD**: login, layout com abas, todas as entidades editáveis (Aparência · Marcas · Unidades · Categorias · Preços · Fotos · Extras · Reservas read-only)
6. **Integração com Chatwoot**: mantém — cada unidade ainda aponta pra um `captain_unit_id`, só que agora também pertence a um tenant

## Fora de escopo (fase futura)

- Onboarding self-service (criar tenant pela UI)
- Billing / planos
- Convite de novos admins
- Roles granulares (por enquanto: owner do tenant = admin total)
- White-label domain customizado (cliente.com em vez de cliente.reserva.app)

---

## Dados conhecidos

- Supabase project: `acdvblhzzaneddlxqyst` (InAudit Hotel), schema: `reserva_hotel`
- Tabelas existentes com dados: `marcas`, `unidades`, `suites`, `suites_unidades`, `precos`, `contas_pagamento`, `reservas`, `fotos_categoria`, `extras`, `reserva_extras`
- Tenant atual (implícito): Grupo Nova / Rede 1001
- Chatwoot dev rodando em `:3000`, reserva-1001 em `:5180`
- Cloudflared tunnel ativo pra testes mobile

---

## File Structure

**Supabase (novo):**
```
reserva-1001/supabase/migrations/
├── 20260414000001_tenants_and_app_config.sql         # novo
├── 20260414000002_add_tenant_id_backfill.sql          # novo
└── 20260414000003_rls_tenant_scoping.sql              # novo
```

**Frontend reserva-1001 (novo):**
```
src/
├── lib/
│   ├── tenant.ts                      # resolver subdomínio → slug
│   ├── appConfig.ts                   # fetch + cache do app_config
│   └── supabase.ts                    # modify — tenant-aware
├── hooks/
│   ├── useAppConfig.ts                # hook do config ativo
│   └── useAuth.ts                     # NOVO — Supabase Auth
├── contexts/
│   └── TenantProvider.tsx             # NOVO — provê tenant + config pros filhos
├── pages/
│   ├── admin/
│   │   ├── AdminLayout.tsx            # shell com nav
│   │   ├── LoginPage.tsx              # login Supabase Auth
│   │   ├── AparenciaTab.tsx           # identidade editável
│   │   ├── MarcasTab.tsx              # CRUD
│   │   ├── UnidadesTab.tsx            # CRUD
│   │   ├── CategoriasTab.tsx          # CRUD
│   │   ├── PrecosTab.tsx              # grid editável
│   │   ├── FotosTab.tsx               # upload + reorder
│   │   ├── ExtrasTab.tsx              # CRUD
│   │   └── ReservasTab.tsx            # read-only + filtros
│   └── ReservationPage.tsx            # era App.tsx — renomeado
├── components/
│   ├── admin/
│   │   ├── AuthGate.tsx               # wrapper que exige login
│   │   ├── ColorPicker.tsx            # novo
│   │   ├── FontSelector.tsx           # novo
│   │   ├── ImageUpload.tsx            # novo (drag-and-drop)
│   │   └── DataTable.tsx              # novo (tabela genérica)
│   └── ... (existentes)
├── router.tsx                          # NOVO — React Router com rotas pública + /admin/*
└── main.tsx                            # modify — renderiza <RouterProvider>
```

**Novos pacotes:**
```
react-router-dom  @tanstack/react-query  react-colorful  react-hook-form  zod
```

---

# PARTE A — Schema multi-tenant (Supabase)

## Task A1: Tabela `tenants` e `app_config`

**Files:**
- Create: `reserva-1001/supabase/migrations/20260414000001_tenants_and_app_config.sql`

- [ ] **Step 1: Criar migration SQL**

```sql
-- Multi-tenancy foundation: tenants + app_config

create table if not exists reserva_hotel.tenants (
  id          bigserial primary key,
  slug        text not null unique,
  nome        text not null,
  ativo       boolean not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create index if not exists idx_tenants_slug on reserva_hotel.tenants(slug);

create table if not exists reserva_hotel.app_config (
  id              bigserial primary key,
  tenant_id       bigint not null unique references reserva_hotel.tenants(id) on delete cascade,
  nome_rede       text not null,              -- "Rede 1001"
  titulo_hero     text not null,              -- "Reserva Rede 1001"
  subtitulo_hero  text,                       -- "Experiência exclusiva"
  tagline         text,                       -- "Escolha, confirme e receba seu PIX na hora."
  footer_text     text,                       -- "© 2026 Rede 1001 · Experiência Exclusiva"
  logo_url        text,                       -- URL (Supabase Storage)
  favicon_url     text,
  cor_primaria    text not null default '#C9A961',   -- champagne
  cor_secundaria  text not null default '#E8B4A0',   -- rose-gold
  cor_fundo       text not null default '#0B0D12',   -- obsidian
  cor_superficie  text not null default '#0F1A2E',   -- midnight
  cor_texto       text not null default '#F5F1E8',   -- ivory
  fonte_display   text not null default 'Fraunces',
  fonte_corpo     text not null default 'Inter',
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);
```

- [ ] **Step 2: Aplicar via MCP `apply_migration`**

Nome da migration: `tenants_and_app_config`. Validar:
```sql
select count(*) from reserva_hotel.tenants;  -- deve retornar 0
select count(*) from reserva_hotel.app_config; -- deve retornar 0
```

- [ ] **Step 3: Commit do arquivo de migration**

```bash
cd /Users/user/Dev/Produtos/Chatwoot-fazer-ai/fazer-ai-kanban/reserva-1001
git add supabase/migrations/20260414000001_tenants_and_app_config.sql
git commit -m "feat: tabelas tenants e app_config (multi-tenant foundation)"
```

---

## Task A2: Adicionar `tenant_id` em todas as tabelas + backfill

**Files:**
- Create: `reserva-1001/supabase/migrations/20260414000002_add_tenant_id_backfill.sql`

- [ ] **Step 1: Criar migration**

```sql
-- Adiciona tenant_id em todas as tabelas existentes + cria tenant default
-- + backfill de tudo pro tenant 1 ("Grupo Nova / Rede 1001")

-- 1. Cria o tenant default
insert into reserva_hotel.tenants (slug, nome, ativo)
values ('grupo-1001', 'Grupo Nova — Rede 1001', true)
on conflict (slug) do nothing;

-- 2. Cria o app_config default
insert into reserva_hotel.app_config
  (tenant_id, nome_rede, titulo_hero, subtitulo_hero, tagline, footer_text,
   cor_primaria, cor_secundaria, cor_fundo, cor_superficie, cor_texto,
   fonte_display, fonte_corpo)
select
  t.id,
  'Rede 1001',
  'Reserva Rede 1001',
  'Experiência exclusiva',
  'Escolha, confirme e receba seu PIX na hora.',
  '© 2026 Rede 1001 · Experiência Exclusiva',
  '#C9A961', '#E8B4A0', '#0B0D12', '#0F1A2E', '#F5F1E8',
  'Fraunces', 'Inter'
from reserva_hotel.tenants t
where t.slug = 'grupo-1001'
on conflict (tenant_id) do nothing;

-- 3. Adiciona tenant_id (nullable inicialmente pra backfill)
alter table reserva_hotel.marcas            add column if not exists tenant_id bigint references reserva_hotel.tenants(id);
alter table reserva_hotel.unidades          add column if not exists tenant_id bigint references reserva_hotel.tenants(id);
alter table reserva_hotel.suites            add column if not exists tenant_id bigint references reserva_hotel.tenants(id);
alter table reserva_hotel.precos            add column if not exists tenant_id bigint references reserva_hotel.tenants(id);
alter table reserva_hotel.contas_pagamento  add column if not exists tenant_id bigint references reserva_hotel.tenants(id);
alter table reserva_hotel.reservas          add column if not exists tenant_id bigint references reserva_hotel.tenants(id);
alter table reserva_hotel.fotos_categoria   add column if not exists tenant_id bigint references reserva_hotel.tenants(id);
alter table reserva_hotel.extras            add column if not exists tenant_id bigint references reserva_hotel.tenants(id);

-- 4. Backfill: atribui todas as rows existentes ao tenant grupo-1001
do $$
declare v_tenant_id bigint;
begin
  select id into v_tenant_id from reserva_hotel.tenants where slug = 'grupo-1001';

  update reserva_hotel.marcas           set tenant_id = v_tenant_id where tenant_id is null;
  update reserva_hotel.unidades         set tenant_id = v_tenant_id where tenant_id is null;
  update reserva_hotel.suites           set tenant_id = v_tenant_id where tenant_id is null;
  update reserva_hotel.precos           set tenant_id = v_tenant_id where tenant_id is null;
  update reserva_hotel.contas_pagamento set tenant_id = v_tenant_id where tenant_id is null;
  update reserva_hotel.reservas         set tenant_id = v_tenant_id where tenant_id is null;
  update reserva_hotel.fotos_categoria  set tenant_id = v_tenant_id where tenant_id is null;
  update reserva_hotel.extras           set tenant_id = v_tenant_id where tenant_id is null;
end $$;

-- 5. Torna tenant_id NOT NULL
alter table reserva_hotel.marcas            alter column tenant_id set not null;
alter table reserva_hotel.unidades          alter column tenant_id set not null;
alter table reserva_hotel.suites            alter column tenant_id set not null;
alter table reserva_hotel.precos            alter column tenant_id set not null;
alter table reserva_hotel.contas_pagamento  alter column tenant_id set not null;
alter table reserva_hotel.reservas          alter column tenant_id set not null;
alter table reserva_hotel.fotos_categoria   alter column tenant_id set not null;
alter table reserva_hotel.extras            alter column tenant_id set not null;

-- 6. Indexes
create index if not exists idx_marcas_tenant           on reserva_hotel.marcas(tenant_id);
create index if not exists idx_unidades_tenant         on reserva_hotel.unidades(tenant_id);
create index if not exists idx_precos_tenant           on reserva_hotel.precos(tenant_id);
create index if not exists idx_reservas_tenant         on reserva_hotel.reservas(tenant_id);
create index if not exists idx_fotos_categoria_tenant  on reserva_hotel.fotos_categoria(tenant_id);
create index if not exists idx_extras_tenant           on reserva_hotel.extras(tenant_id);
```

- [ ] **Step 2: Aplicar via MCP**

Validar:
```sql
select (select count(*) from reserva_hotel.tenants) as tenants,
       (select count(*) from reserva_hotel.app_config) as configs,
       (select count(*) from reserva_hotel.marcas where tenant_id is null) as marcas_sem_tenant;
```

Expected: `tenants=1, configs=1, marcas_sem_tenant=0`

- [ ] **Step 3: Commit**

```bash
git add supabase/migrations/20260414000002_add_tenant_id_backfill.sql
git commit -m "feat: adiciona tenant_id em todas tabelas + backfill grupo-1001"
```

---

## Task A3: RLS tenant scoping

**Files:**
- Create: `reserva-1001/supabase/migrations/20260414000003_rls_tenant_scoping.sql`

- [ ] **Step 1: Criar migration RLS**

A ideia: RLS lê o `tenant_id` de um claim customizado no JWT. Pro anon (acesso público), a aplicação passa o tenant via query, não via JWT (porque anon não loga).

**Estratégia simplificada:**
- Tabelas de catálogo (marcas, unidades, categorias, precos, fotos, extras) → RLS permite SELECT público quando `tenant_id = current_setting('app.current_tenant_id', true)::bigint`
- `app_config` e `tenants` → SELECT público (são lidas pro tenant resolver)
- Tabelas sensíveis (reservas, contas_pagamento) → apenas service_role

Para o anon setar o contexto, usa-se `set_config('app.current_tenant_id', '1', false)` via RPC. Ou mais simples: o frontend passa `eq('tenant_id', X)` em cada query. **Vamos usar essa segunda abordagem** porque é mais explícita e não depende de magic setting.

Migration apenas garante que as policies existentes continuam permitindo leitura pública das tabelas de catálogo. As queries do frontend passam a filtrar por tenant_id explicitamente.

```sql
-- Garante que as tabelas publicas tem RLS ON e policy de leitura.
alter table reserva_hotel.tenants enable row level security;
alter table reserva_hotel.app_config enable row level security;

drop policy if exists "public_read_tenants" on reserva_hotel.tenants;
create policy "public_read_tenants" on reserva_hotel.tenants
  for select using (ativo = true);

drop policy if exists "public_read_app_config" on reserva_hotel.app_config;
create policy "public_read_app_config" on reserva_hotel.app_config
  for select using (true);

-- As outras tabelas (marcas/unidades/etc) ja tem grants do anon feitos
-- numa migration anterior; nao precisa mexer.
```

- [ ] **Step 2: Aplicar via MCP + validar**

```bash
curl -s -o /tmp/t.json -w "HTTP %{http_code}\n" \
  -H "apikey: <ANON_KEY>" \
  -H "Accept-Profile: reserva_hotel" \
  "https://acdvblhzzaneddlxqyst.supabase.co/rest/v1/tenants?select=id,slug,nome"
cat /tmp/t.json
```

Expected: `[{"id":1,"slug":"grupo-1001","nome":"Grupo Nova — Rede 1001"}]`

- [ ] **Step 3: Grant explícito pro anon ler tenants + app_config**

```sql
grant select on reserva_hotel.tenants to anon, authenticated;
grant select on reserva_hotel.app_config to anon, authenticated;
```

Aplicar via MCP.

- [ ] **Step 4: Commit**

```bash
git add supabase/migrations/20260414000003_rls_tenant_scoping.sql
git commit -m "feat: RLS policies + grants pra tenants/app_config publicas"
```

---

# PARTE B — Supabase Auth + admin user seed

## Task B1: Habilitar Supabase Auth + coluna `tenant_id` no user_metadata

**Files:** nenhum arquivo novo — config no Supabase dashboard.

- [ ] **Step 1: Via Supabase dashboard**

No console do projeto `acdvblhzzaneddlxqyst`:
1. Authentication → Providers → Email → enable (se ainda não estiver)
2. Authentication → Settings → desmarcar "Enable email confirmations" (pra MVP — agiliza login no dev)

- [ ] **Step 2: Criar usuário admin de teste via Rails runner no Chatwoot** (ou via supabase CLI)

```bash
cd /Users/user/Dev/Produtos/Chatwoot-fazer-ai/fazer-ai-kanban/reserva-1001
# Via API REST do Supabase (usa service_role key)
curl -X POST "https://acdvblhzzaneddlxqyst.supabase.co/auth/v1/admin/users" \
  -H "apikey: <SERVICE_ROLE_KEY>" \
  -H "Authorization: Bearer <SERVICE_ROLE_KEY>" \
  -H "Content-Type: application/json" \
  -d '{
    "email": "admin@reserva.test",
    "password": "admin123",
    "email_confirm": true,
    "user_metadata": { "tenant_id": 1, "role": "tenant_admin" }
  }'
```

**Nota:** `SERVICE_ROLE_KEY` precisa ser obtido via MCP (`mcp__claude_ai_supabase__get_publishable_keys` não retorna service_role — preciso buscar via outra rota, ou pedir ao usuário).

**Alternativa simpler pro MVP:** criar o usuário via Supabase dashboard → Authentication → Add user manually, e setar `tenant_id: 1` em "Raw User Meta Data".

- [ ] **Step 3: Documentar no README**

Adicionar ao `reserva-1001/README.md` seção "Admin de teste" com email/senha.

---

## Task B2: Tabela auxiliar `tenant_members` (quem pode admin do quê)

**Files:**
- Create: `reserva-1001/supabase/migrations/20260414000004_tenant_members.sql`

- [ ] **Step 1: Migration**

```sql
create table if not exists reserva_hotel.tenant_members (
  id          bigserial primary key,
  tenant_id   bigint not null references reserva_hotel.tenants(id) on delete cascade,
  user_id     uuid not null,                  -- auth.users.id
  role        text not null default 'admin',  -- 'admin' | 'viewer'
  created_at  timestamptz not null default now(),
  unique (tenant_id, user_id)
);

create index if not exists idx_tenant_members_user on reserva_hotel.tenant_members(user_id);
create index if not exists idx_tenant_members_tenant on reserva_hotel.tenant_members(tenant_id);

alter table reserva_hotel.tenant_members enable row level security;

-- Um user pode ler os tenants aos quais pertence
create policy "members_read_own" on reserva_hotel.tenant_members
  for select using (auth.uid() = user_id);

grant select on reserva_hotel.tenant_members to authenticated;
```

Aplicar + seed do primeiro admin:
```sql
insert into reserva_hotel.tenant_members (tenant_id, user_id, role)
select 1, id, 'admin' from auth.users where email = 'admin@reserva.test'
on conflict do nothing;
```

- [ ] **Step 2: Commit**

```bash
git add supabase/migrations/20260414000004_tenant_members.sql
git commit -m "feat: tabela tenant_members pra escopar admins por tenant"
```

---

# PARTE C — Frontend: tenant resolver + theming dinâmico

## Task C1: `src/lib/tenant.ts` — resolver subdomínio

**Files:**
- Create: `reserva-1001/src/lib/tenant.ts`
- Modify: `reserva-1001/.env.local.example` — adicionar `VITE_DEFAULT_TENANT_SLUG`

- [ ] **Step 1: Criar parser**

```ts
// Resolve o tenant slug a partir do hostname.
// Prod:   https://prime.reserva.fazer.ai  → slug = "prime"
// Dev:    http://localhost:5180           → fallback pro VITE_DEFAULT_TENANT_SLUG
// Custom: https://reserva.motelxyz.com    → host registrado = tenant slug (v2)

export function resolveTenantSlug(): string {
  if (typeof window === 'undefined') {
    return import.meta.env.VITE_DEFAULT_TENANT_SLUG || 'grupo-1001'
  }

  const host = window.location.hostname

  // dev / localhost
  if (host === 'localhost' || host.startsWith('127.') || host.endsWith('.local')) {
    return import.meta.env.VITE_DEFAULT_TENANT_SLUG || 'grupo-1001'
  }

  // cloudflared tunnel: <random>.trycloudflare.com — usa default tb
  if (host.endsWith('.trycloudflare.com')) {
    return import.meta.env.VITE_DEFAULT_TENANT_SLUG || 'grupo-1001'
  }

  // Padrão SaaS: <slug>.reserva.fazer.ai
  // Pega a primeira parte do host (antes do primeiro ponto)
  const parts = host.split('.')
  return parts[0] || 'grupo-1001'
}
```

Edit `.env.local.example` e `.env.local`:
```
VITE_DEFAULT_TENANT_SLUG=grupo-1001
```

- [ ] **Step 2: Commit**

```bash
pnpm typecheck
git add src/lib/tenant.ts .env.local.example
git commit -m "feat: resolver de tenant slug por subdominio"
```

---

## Task C2: `src/lib/appConfig.ts` + tipos do Supabase regenerados

**Files:**
- Create: `reserva-1001/src/lib/appConfig.ts`
- Modify: `reserva-1001/src/types/database.ts` (regenerar via `supabase gen types`)

- [ ] **Step 1: Regenerar types**

```bash
cd /Users/user/Dev/Produtos/Chatwoot-fazer-ai/fazer-ai-kanban/reserva-1001
pnpm supabase:types
```

Isso pega os novos campos `tenant_id`, tabelas `tenants`, `app_config`, `tenant_members`.

- [ ] **Step 2: Criar `appConfig.ts`**

```ts
import { supabase } from './supabase'
import type { Database } from '@/types/database'

export type Tenant = Database['reserva_hotel']['Tables']['tenants']['Row']
export type AppConfig = Database['reserva_hotel']['Tables']['app_config']['Row']

export interface LoadedTenantContext {
  tenant: Tenant
  config: AppConfig
}

export async function loadTenantContext(slug: string): Promise<LoadedTenantContext | null> {
  const { data: tenant, error: tenantError } = await supabase
    .from('tenants')
    .select('*')
    .eq('slug', slug)
    .eq('ativo', true)
    .maybeSingle()

  if (tenantError) throw new Error(tenantError.message)
  if (!tenant) return null

  const { data: config, error: configError } = await supabase
    .from('app_config')
    .select('*')
    .eq('tenant_id', tenant.id)
    .maybeSingle()

  if (configError) throw new Error(configError.message)
  if (!config) return null

  return { tenant, config }
}
```

- [ ] **Step 3: Typecheck + commit**

```bash
pnpm typecheck
git add src/lib/appConfig.ts src/types/database.ts
git commit -m "feat: loadTenantContext carrega tenant + app_config por slug"
```

---

## Task C3: `TenantProvider` + `useAppConfig` hook

**Files:**
- Create: `reserva-1001/src/contexts/TenantProvider.tsx`
- Create: `reserva-1001/src/hooks/useAppConfig.ts`

- [ ] **Step 1: Criar contexto**

```tsx
// src/contexts/TenantProvider.tsx
import { createContext, useContext, useEffect, useState, type ReactNode } from 'react'
import type { LoadedTenantContext } from '@/lib/appConfig'
import { loadTenantContext } from '@/lib/appConfig'
import { resolveTenantSlug } from '@/lib/tenant'

interface TenantContextValue {
  loading: boolean
  error: string | null
  context: LoadedTenantContext | null
  refresh: () => Promise<void>
}

const TenantContext = createContext<TenantContextValue | null>(null)

export function TenantProvider({ children }: { children: ReactNode }) {
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [context, setContext] = useState<LoadedTenantContext | null>(null)

  const load = async () => {
    setLoading(true)
    setError(null)
    try {
      const slug = resolveTenantSlug()
      const ctx = await loadTenantContext(slug)
      if (!ctx) {
        setError(`Tenant "${slug}" não encontrado ou inativo.`)
      } else {
        setContext(ctx)
        applyTheme(ctx)
        applyMetadata(ctx)
      }
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Erro ao carregar tenant')
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => {
    void load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  return (
    <TenantContext.Provider value={{ loading, error, context, refresh: load }}>
      {children}
    </TenantContext.Provider>
  )
}

export function useTenant() {
  const ctx = useContext(TenantContext)
  if (!ctx) throw new Error('useTenant must be used inside <TenantProvider>')
  return ctx
}

function applyTheme(ctx: LoadedTenantContext) {
  const { config } = ctx
  const root = document.documentElement
  root.style.setProperty('--color-champagne', config.cor_primaria)
  root.style.setProperty('--color-rose-gold', config.cor_secundaria)
  root.style.setProperty('--color-obsidian', config.cor_fundo)
  root.style.setProperty('--color-midnight', config.cor_superficie)
  root.style.setProperty('--color-ivory', config.cor_texto)

  // Fontes via Google Fonts dynamic <link>
  loadGoogleFont(config.fonte_display)
  loadGoogleFont(config.fonte_corpo)
  root.style.setProperty('--font-serif', `'${config.fonte_display}', Georgia, serif`)
  root.style.setProperty('--font-sans', `'${config.fonte_corpo}', system-ui, sans-serif`)
}

function loadGoogleFont(family: string) {
  if (!family) return
  const id = `gfont-${family.replace(/\s+/g, '-').toLowerCase()}`
  if (document.getElementById(id)) return
  const link = document.createElement('link')
  link.id = id
  link.rel = 'stylesheet'
  link.href = `https://fonts.googleapis.com/css2?family=${encodeURIComponent(family)}:wght@400;500;600;700&display=swap`
  document.head.appendChild(link)
}

function applyMetadata(ctx: LoadedTenantContext) {
  const { config } = ctx
  document.title = config.titulo_hero
  if (config.favicon_url) {
    let link = document.querySelector<HTMLLinkElement>("link[rel='icon']")
    if (!link) {
      link = document.createElement('link')
      link.rel = 'icon'
      document.head.appendChild(link)
    }
    link.href = config.favicon_url
  }
}
```

- [ ] **Step 2: Hook de conveniência**

```ts
// src/hooks/useAppConfig.ts
import { useTenant } from '@/contexts/TenantProvider'

export function useAppConfig() {
  const { context } = useTenant()
  return context?.config ?? null
}

export function useTenantId() {
  const { context } = useTenant()
  return context?.tenant.id ?? null
}
```

- [ ] **Step 3: Commit**

```bash
pnpm typecheck
git add src/contexts/TenantProvider.tsx src/hooks/useAppConfig.ts
git commit -m "feat: TenantProvider aplica tema e metadados dinamicos"
```

---

## Task C4: Envolver o app no `TenantProvider` + usar config na página pública

**Files:**
- Modify: `reserva-1001/src/main.tsx`
- Modify: `reserva-1001/src/App.tsx`
- Modify: `reserva-1001/src/services/catalogoService.ts` — filtrar por `tenant_id`

- [ ] **Step 1: main.tsx envolve tudo**

```tsx
import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import './index.css'
import App from './App'
import { TenantProvider } from '@/contexts/TenantProvider'

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <TenantProvider>
      <App />
    </TenantProvider>
  </StrictMode>
)
```

- [ ] **Step 2: App.tsx usa config**

Substituir strings hardcoded por `useAppConfig()`:

```tsx
import { useAppConfig } from '@/hooks/useAppConfig'
import { useTenant } from '@/contexts/TenantProvider'
import { ReservationFlow } from '@/components/reservation/ReservationFlow'

export default function App() {
  const { loading, error, context } = useTenant()
  const config = useAppConfig()

  if (loading) {
    return <div className="min-h-screen flex items-center justify-center text-ivory">Carregando...</div>
  }
  if (error || !config) {
    return (
      <div className="min-h-screen flex items-center justify-center text-ruby p-6 text-center">
        {error ?? 'Configuração não encontrada'}
      </div>
    )
  }

  return (
    <main className="min-h-screen flex flex-col items-center px-6 py-12">
      <header className="text-center mb-10">
        {config.subtitulo_hero && (
          <p className="font-sans text-sm uppercase tracking-[0.3em] text-rose-gold mb-4">
            {config.subtitulo_hero}
          </p>
        )}
        <h1 className="font-serif text-5xl md:text-6xl text-gradient-gold mb-3">
          {config.titulo_hero}
        </h1>
        {config.tagline && (
          <p className="font-sans text-slate text-lg">{config.tagline}</p>
        )}
      </header>

      <ReservationFlow />

      {config.footer_text && (
        <footer className="mt-16 text-slate text-xs uppercase tracking-widest">
          {config.footer_text}
        </footer>
      )}
    </main>
  )
}
```

- [ ] **Step 3: `catalogoService.ts` filtra por tenant**

Cada query do catálogo precisa passar `tenant_id`. Modificar todas as funções:

```ts
async listMarcas(tenantId: number): Promise<Marca[]> {
  const { data, error } = await supabase
    .from('marcas')
    .select('*')
    .eq('tenant_id', tenantId)
    .eq('ativa', true)
    .order('nome')
  if (error) throw new Error(error.message)
  return data ?? []
}
// idem pras outras: listUnidades, findPreco, listFotos, listExtras
// todas recebem tenantId e filtram por ele
```

- [ ] **Step 4: `useReservationForm` passa `tenantId` pras queries**

```ts
import { useTenantId } from '@/hooks/useAppConfig'

export function useReservationForm(initialPrefill?: PrefillData) {
  const tenantId = useTenantId()
  // ...
  useEffect(() => {
    if (!tenantId) return
    catalogoService.listMarcas(tenantId).then(setMarcas).catch(/* ... */)
  }, [tenantId])
  // idem pros outros useEffects — todos dependem de tenantId
}
```

- [ ] **Step 5: Typecheck + test + commit**

```bash
pnpm typecheck
pnpm test
pnpm build
git add src/main.tsx src/App.tsx src/services/catalogoService.ts src/hooks/useReservationForm.ts
git commit -m "feat: app usa config dinamico + queries filtradas por tenant"
```

- [ ] **Step 6: Teste manual**

```bash
pnpm dev
```

Abre `http://localhost:5180/`. Deve continuar funcionando igual (lê tenant `grupo-1001` como fallback). Título, subtítulo, tagline, cores — tudo vem do `app_config` agora.

---

# PARTE D — Auth + admin shell

## Task D1: Hook `useAuth` + integração Supabase

**Files:**
- Create: `reserva-1001/src/hooks/useAuth.ts`

- [ ] **Step 1: Criar hook**

```ts
// src/hooks/useAuth.ts
import { useEffect, useState } from 'react'
import type { Session, User } from '@supabase/supabase-js'
import { supabase } from '@/lib/supabase'

export function useAuth() {
  const [session, setSession] = useState<Session | null>(null)
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    supabase.auth.getSession().then(({ data }) => {
      setSession(data.session)
      setLoading(false)
    })
    const { data: sub } = supabase.auth.onAuthStateChange((_event, newSession) => {
      setSession(newSession)
    })
    return () => sub.subscription.unsubscribe()
  }, [])

  const signIn = async (email: string, password: string) => {
    const { error } = await supabase.auth.signInWithPassword({ email, password })
    if (error) throw new Error(error.message)
  }

  const signOut = async () => {
    await supabase.auth.signOut()
  }

  return { session, user: session?.user ?? null, loading, signIn, signOut }
}

export function useAuthenticatedTenantId(user: User | null): number | null {
  const rawTid = user?.user_metadata?.tenant_id
  const parsed = typeof rawTid === 'number' ? rawTid : Number(rawTid)
  return Number.isFinite(parsed) && parsed > 0 ? parsed : null
}
```

- [ ] **Step 2: Commit**

```bash
pnpm typecheck
git add src/hooks/useAuth.ts
git commit -m "feat: useAuth hook integrado ao Supabase Auth"
```

---

## Task D2: Rotas + AdminLayout + LoginPage

**Files:**
- Install: `pnpm add react-router-dom`
- Create: `reserva-1001/src/router.tsx`
- Create: `reserva-1001/src/pages/admin/LoginPage.tsx`
- Create: `reserva-1001/src/pages/admin/AdminLayout.tsx`
- Create: `reserva-1001/src/components/admin/AuthGate.tsx`
- Modify: `reserva-1001/src/main.tsx`
- Rename: `reserva-1001/src/App.tsx` → `reserva-1001/src/pages/ReservationPage.tsx`

- [ ] **Step 1: Instalar React Router**

```bash
cd /Users/user/Dev/Produtos/Chatwoot-fazer-ai/fazer-ai-kanban/reserva-1001
pnpm add react-router-dom
```

- [ ] **Step 2: Renomear App.tsx → ReservationPage.tsx**

Mover `src/App.tsx` → `src/pages/ReservationPage.tsx`. Ajustar imports.

- [ ] **Step 3: Router**

```tsx
// src/router.tsx
import { createBrowserRouter, RouterProvider, Navigate } from 'react-router-dom'
import { ReservationPage } from '@/pages/ReservationPage'
import { LoginPage } from '@/pages/admin/LoginPage'
import { AdminLayout } from '@/pages/admin/AdminLayout'
import { AparenciaTab } from '@/pages/admin/AparenciaTab'
// ... imports das outras abas

const router = createBrowserRouter([
  { path: '/', element: <ReservationPage /> },
  { path: '/admin/login', element: <LoginPage /> },
  {
    path: '/admin',
    element: <AdminLayout />,
    children: [
      { index: true, element: <Navigate to="aparencia" replace /> },
      { path: 'aparencia', element: <AparenciaTab /> },
      // { path: 'marcas', element: <MarcasTab /> },
      // etc
    ],
  },
])

export function AppRouter() {
  return <RouterProvider router={router} />
}
```

- [ ] **Step 4: AuthGate**

```tsx
// src/components/admin/AuthGate.tsx
import { Navigate, useLocation } from 'react-router-dom'
import { useAuth } from '@/hooks/useAuth'

export function AuthGate({ children }: { children: React.ReactNode }) {
  const { session, loading } = useAuth()
  const location = useLocation()

  if (loading) return <div className="p-12 text-ivory">Carregando...</div>
  if (!session) return <Navigate to="/admin/login" state={{ from: location }} replace />
  return <>{children}</>
}
```

- [ ] **Step 5: LoginPage**

```tsx
// src/pages/admin/LoginPage.tsx
import { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { useAuth } from '@/hooks/useAuth'
import { FormField } from '@/components/FormField'
import { Button } from '@/components/ui/button'

export function LoginPage() {
  const { signIn } = useAuth()
  const navigate = useNavigate()
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [error, setError] = useState<string | null>(null)
  const [submitting, setSubmitting] = useState(false)

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    setSubmitting(true)
    setError(null)
    try {
      await signIn(email, password)
      navigate('/admin')
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Erro ao entrar')
    } finally {
      setSubmitting(false)
    }
  }

  return (
    <main className="min-h-screen flex items-center justify-center px-6">
      <form onSubmit={handleSubmit} className="w-full max-w-md space-y-6 rounded-2xl border border-champagne/20 bg-midnight/60 p-8 backdrop-blur">
        <h1 className="font-serif text-3xl text-gradient-gold text-center">Painel Administrativo</h1>
        <FormField
          label="E-mail"
          required
          type="email"
          value={email}
          onChange={(e) => setEmail(e.target.value)}
        />
        <FormField
          label="Senha"
          required
          type="password"
          value={password}
          onChange={(e) => setPassword(e.target.value)}
        />
        {error && <div className="rounded-xl border border-ruby/40 bg-ruby/10 p-3 text-ivory text-sm">{error}</div>}
        <Button type="submit" variant="primary" size="lg" className="w-full" disabled={submitting}>
          {submitting ? 'Entrando...' : 'Entrar'}
        </Button>
      </form>
    </main>
  )
}
```

- [ ] **Step 6: AdminLayout**

```tsx
// src/pages/admin/AdminLayout.tsx
import { NavLink, Outlet } from 'react-router-dom'
import { useAuth } from '@/hooks/useAuth'
import { AuthGate } from '@/components/admin/AuthGate'
import { Button } from '@/components/ui/button'

const TABS = [
  { to: 'aparencia', label: 'Aparência' },
  { to: 'marcas', label: 'Marcas' },
  { to: 'unidades', label: 'Unidades' },
  { to: 'categorias', label: 'Categorias' },
  { to: 'precos', label: 'Preços' },
  { to: 'fotos', label: 'Fotos' },
  { to: 'extras', label: 'Extras' },
  { to: 'reservas', label: 'Reservas' },
]

export function AdminLayout() {
  const { signOut, user } = useAuth()

  return (
    <AuthGate>
      <div className="min-h-screen flex flex-col">
        <header className="border-b border-champagne/20 bg-midnight/60 backdrop-blur px-6 py-4 flex items-center justify-between">
          <h1 className="font-serif text-2xl text-champagne">Painel Administrativo</h1>
          <div className="flex items-center gap-3 text-sm text-slate">
            <span>{user?.email}</span>
            <Button variant="ghost" size="sm" onClick={() => signOut()}>Sair</Button>
          </div>
        </header>
        <nav className="border-b border-champagne/10 bg-obsidian/60 px-6 py-3 flex gap-1 overflow-x-auto">
          {TABS.map((tab) => (
            <NavLink
              key={tab.to}
              to={tab.to}
              className={({ isActive }) =>
                `px-4 py-2 rounded-lg text-sm font-sans transition ${
                  isActive
                    ? 'bg-champagne text-obsidian font-semibold'
                    : 'text-ivory hover:bg-champagne/10'
                }`
              }
            >
              {tab.label}
            </NavLink>
          ))}
        </nav>
        <div className="flex-1 p-6 md:p-10">
          <Outlet />
        </div>
      </div>
    </AuthGate>
  )
}
```

- [ ] **Step 7: main.tsx usa router**

```tsx
import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import './index.css'
import { AppRouter } from './router'
import { TenantProvider } from '@/contexts/TenantProvider'

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <TenantProvider>
      <AppRouter />
    </TenantProvider>
  </StrictMode>
)
```

- [ ] **Step 8: Validar + commit**

```bash
pnpm typecheck
pnpm build
git add src/router.tsx src/pages/admin/ src/components/admin/AuthGate.tsx src/main.tsx src/pages/ReservationPage.tsx package.json pnpm-lock.yaml
git rm src/App.tsx 2>/dev/null || true
git commit -m "feat: rotas + admin shell + login Supabase Auth"
```

---

## Task D3: Aba Aparência (identidade editável)

**Files:**
- Create: `reserva-1001/src/pages/admin/AparenciaTab.tsx`
- Install: `pnpm add react-colorful react-hook-form zod @hookform/resolvers`

- [ ] **Step 1: Install deps**

```bash
pnpm add react-colorful react-hook-form zod @hookform/resolvers
```

- [ ] **Step 2: AparenciaTab**

Form com:
- Nome da rede, título hero, subtítulo, tagline, footer text (campos texto)
- Logo URL, favicon URL (upload no Task D8 — por enquanto só URL text input)
- Cor primária, secundária, fundo, superfície, texto (via `react-colorful` `HexColorPicker`)
- Fonte display, corpo (dropdown com opções: Fraunces, Playfair Display, Cormorant Garamond, Lora, Inter, Poppins, Manrope, DM Sans)
- Botão "Salvar" que faz `supabase.from('app_config').update(...).eq('tenant_id', tenantId)`
- Botão "Preview" que aplica as mudanças temporariamente via CSS variables sem salvar
- Após salvar, refresh do `TenantProvider` pra aplicar no app inteiro

Código completo:

```tsx
import { useEffect, useState } from 'react'
import { HexColorPicker } from 'react-colorful'
import { supabase } from '@/lib/supabase'
import { useTenant } from '@/contexts/TenantProvider'
import { FormField } from '@/components/FormField'
import { SelectField } from '@/components/SelectField'
import { Button } from '@/components/ui/button'
import { useAuth } from '@/hooks/useAuth'
import { useAuthenticatedTenantId } from '@/hooks/useAuth'

const FONT_OPTIONS = [
  { value: 'Fraunces', label: 'Fraunces' },
  { value: 'Playfair Display', label: 'Playfair Display' },
  { value: 'Cormorant Garamond', label: 'Cormorant Garamond' },
  { value: 'Lora', label: 'Lora' },
  { value: 'Inter', label: 'Inter' },
  { value: 'Poppins', label: 'Poppins' },
  { value: 'Manrope', label: 'Manrope' },
  { value: 'DM Sans', label: 'DM Sans' },
]

export function AparenciaTab() {
  const { context, refresh } = useTenant()
  const { user } = useAuth()
  const tenantId = useAuthenticatedTenantId(user)
  const [form, setForm] = useState(context?.config ?? null)
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    setForm(context?.config ?? null)
  }, [context])

  if (!form || !tenantId) return <p className="text-slate">Carregando...</p>

  const update = <K extends keyof typeof form>(key: K, value: (typeof form)[K]) => {
    setForm({ ...form, [key]: value })
  }

  const handleSave = async () => {
    if (!form || !tenantId) return
    setSaving(true)
    setError(null)
    try {
      const { error: err } = await supabase
        .from('app_config')
        .update({
          nome_rede: form.nome_rede,
          titulo_hero: form.titulo_hero,
          subtitulo_hero: form.subtitulo_hero,
          tagline: form.tagline,
          footer_text: form.footer_text,
          logo_url: form.logo_url,
          favicon_url: form.favicon_url,
          cor_primaria: form.cor_primaria,
          cor_secundaria: form.cor_secundaria,
          cor_fundo: form.cor_fundo,
          cor_superficie: form.cor_superficie,
          cor_texto: form.cor_texto,
          fonte_display: form.fonte_display,
          fonte_corpo: form.fonte_corpo,
        })
        .eq('tenant_id', tenantId)

      if (err) throw new Error(err.message)
      await refresh()
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Erro ao salvar')
    } finally {
      setSaving(false)
    }
  }

  return (
    <div className="max-w-3xl space-y-8">
      <section className="space-y-4 rounded-2xl border border-champagne/20 bg-midnight/40 p-6">
        <h2 className="font-serif text-2xl text-champagne">Textos</h2>
        <FormField label="Nome da rede" value={form.nome_rede} onChange={(e) => update('nome_rede', e.target.value)} required />
        <FormField label="Título da página" value={form.titulo_hero} onChange={(e) => update('titulo_hero', e.target.value)} required />
        <FormField label="Subtítulo" value={form.subtitulo_hero ?? ''} onChange={(e) => update('subtitulo_hero', e.target.value)} />
        <FormField label="Tagline" value={form.tagline ?? ''} onChange={(e) => update('tagline', e.target.value)} />
        <FormField label="Footer" value={form.footer_text ?? ''} onChange={(e) => update('footer_text', e.target.value)} />
      </section>

      <section className="space-y-4 rounded-2xl border border-champagne/20 bg-midnight/40 p-6">
        <h2 className="font-serif text-2xl text-champagne">Imagens</h2>
        <FormField label="URL do logo" value={form.logo_url ?? ''} onChange={(e) => update('logo_url', e.target.value)} placeholder="https://..." />
        <FormField label="URL do favicon" value={form.favicon_url ?? ''} onChange={(e) => update('favicon_url', e.target.value)} placeholder="https://..." />
      </section>

      <section className="space-y-4 rounded-2xl border border-champagne/20 bg-midnight/40 p-6">
        <h2 className="font-serif text-2xl text-champagne">Cores</h2>
        <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
          <ColorField label="Primária" value={form.cor_primaria} onChange={(v) => update('cor_primaria', v)} />
          <ColorField label="Secundária" value={form.cor_secundaria} onChange={(v) => update('cor_secundaria', v)} />
          <ColorField label="Fundo" value={form.cor_fundo} onChange={(v) => update('cor_fundo', v)} />
          <ColorField label="Superfície" value={form.cor_superficie} onChange={(v) => update('cor_superficie', v)} />
          <ColorField label="Texto" value={form.cor_texto} onChange={(v) => update('cor_texto', v)} />
        </div>
      </section>

      <section className="space-y-4 rounded-2xl border border-champagne/20 bg-midnight/40 p-6">
        <h2 className="font-serif text-2xl text-champagne">Tipografia</h2>
        <SelectField label="Fonte dos títulos (display)" value={form.fonte_display} onChange={(e) => update('fonte_display', e.target.value)} options={FONT_OPTIONS} />
        <SelectField label="Fonte do corpo" value={form.fonte_corpo} onChange={(e) => update('fonte_corpo', e.target.value)} options={FONT_OPTIONS} />
      </section>

      {error && <div className="rounded-xl border border-ruby/40 bg-ruby/10 p-4 text-ivory">{error}</div>}

      <div className="flex gap-3">
        <Button variant="primary" size="lg" onClick={handleSave} disabled={saving}>
          {saving ? 'Salvando...' : 'Salvar aparência'}
        </Button>
      </div>
    </div>
  )
}

function ColorField({ label, value, onChange }: { label: string; value: string; onChange: (v: string) => void }) {
  const [open, setOpen] = useState(false)
  return (
    <div>
      <label className="font-sans text-xs uppercase tracking-widest text-champagne">{label}</label>
      <div className="mt-2 flex items-center gap-3">
        <button
          type="button"
          className="h-10 w-10 rounded-lg border border-champagne/30"
          style={{ backgroundColor: value }}
          onClick={() => setOpen(!open)}
        />
        <FormField label="" value={value} onChange={(e) => onChange(e.target.value)} className="flex-1" />
      </div>
      {open && (
        <div className="mt-2">
          <HexColorPicker color={value} onChange={onChange} />
        </div>
      )}
    </div>
  )
}
```

- [ ] **Step 3: Typecheck + commit**

```bash
pnpm typecheck
git add src/pages/admin/AparenciaTab.tsx package.json pnpm-lock.yaml
git commit -m "feat: aba Aparencia edita identidade visual do tenant"
```

---

# PARTE E — Abas de CRUD

As tasks D4 a D11 do escopo original ficam aqui. Cada uma segue o mesmo padrão:
- Query do Supabase com `eq('tenant_id', tenantId)`
- Lista em tabela com `<DataTable>` genérico
- Botão "+ Novo" abre modal de form
- Edit inline ou modal
- Delete com confirmação

Devido ao tamanho, vou definir **um template reutilizável** e cada task referencia ele.

## Task E1: Componente genérico `<DataTable>` + `useCrud` hook

**Files:**
- Create: `reserva-1001/src/components/admin/DataTable.tsx`
- Create: `reserva-1001/src/hooks/useCrud.ts`

- [ ] **Step 1: DataTable (tabela simples com actions)**

Template:
```tsx
// Tabela com colunas configuráveis + actions (editar, deletar)
interface Column<T> { key: keyof T; label: string; render?: (row: T) => React.ReactNode }
interface Props<T> {
  rows: T[]
  columns: Column<T>[]
  onEdit?: (row: T) => void
  onDelete?: (row: T) => void
  loading?: boolean
}
// ... implementação (~80 linhas, estilo premium)
```

- [ ] **Step 2: `useCrud` hook**

```tsx
// Encapsula list/create/update/delete pra uma tabela do Supabase filtrada por tenant_id
export function useCrud<T extends { id: number | string }>(tableName: string) {
  const tenantId = useAuthenticatedTenantId(user)
  // retorna { rows, loading, error, refresh, create, update, remove }
}
```

- [ ] **Step 3: Commit**

---

## Tasks E2-E8: Cada aba de CRUD

Cada uma segue o mesmo template:

### Task E2: MarcasTab
Form: `nome`, `descricao`, `categorias` (array text), `permanencias` (array text), `ativa`.

### Task E3: UnidadesTab
Form: `nome`, `id_marca` (dropdown), `chatwoot_unit_id` (number — vinculação ao Chatwoot), `endereco`, `telefone`, `email`, `categorias_visiveis` (array), `ativa`.

### Task E4: CategoriasTab
**Nota:** hoje as categorias moram no array `marcas.categorias`. Vou manter assim — a aba Categorias é na verdade uma view agrupada que edita o array da marca selecionada.

### Task E5: PrecosTab
Grid editável por categoria × permanência. Input numérico inline. Salva em batch.

### Task E6: FotosTab
Upload drag-and-drop pro Supabase Storage (`reserva-1001-fotos` bucket) + thumbnail + reorder + delete.

### Task E7: ExtrasTab
Form: `titulo`, `descricao`, `preco`, `imagem_url`, `ativo`, `ordem`.

### Task E8: ReservasTab (read-only)
Lista com filtros (status, data, unidade). Click numa reserva mostra detalhes + link pra conversa no Chatwoot (`{CHATWOOT_URL}/app/accounts/1/conversations/{id}`).

---

# PARTE F — Deploy + testes

## Task F1: Configurar Vercel wildcard domain

- [ ] Criar projeto Vercel
- [ ] Apontar domínio `reserva.fazer.ai` (ou subdomínio que você escolher) via DNS CNAME
- [ ] Configurar wildcard `*.reserva.fazer.ai` no Vercel Project Settings → Domains
- [ ] Env vars de produção: `VITE_SUPABASE_URL`, `VITE_SUPABASE_ANON_KEY`, `VITE_SUPABASE_SCHEMA=reserva_hotel`, `VITE_CHATWOOT_API_URL`, `VITE_CHATWOOT_API_TOKEN`, `VITE_DEFAULT_TENANT_SLUG=grupo-1001`

## Task F2: Teste ponta-a-ponta multi-tenant

- Criar um segundo tenant manualmente (`INSERT INTO tenants (slug, nome) VALUES ('motel-teste', 'Motel Teste')`)
- Criar `app_config` pra ele com nome/cores diferentes
- Abrir `motel-teste.reserva.fazer.ai` e `grupo-1001.reserva.fazer.ai` — cada um mostra sua identidade

## Task F3: README atualizado

Documentar:
- Como criar um novo tenant
- Como subir env vars
- Como acessar o admin
- Limitações conhecidas (não tem onboarding self-service)

---

## Critérios de conclusão

**Multi-tenancy:**
- [ ] Todas as tabelas têm `tenant_id`
- [ ] Dados existentes backfilled pro tenant `grupo-1001`
- [ ] Frontend resolve subdomínio → slug → tenant
- [ ] `TenantProvider` aplica tema (CSS vars) e metadados (title, favicon) dinamicamente

**Identidade editável:**
- [ ] Aba "Aparência" permite editar: nome, título, subtítulo, tagline, footer, logo URL, favicon URL, 5 cores, 2 fontes
- [ ] Mudanças refletem no app após salvar (via `refresh` do TenantProvider)

**Admin:**
- [ ] Login via Supabase Auth funciona
- [ ] `/admin/login` → após login → redirect pra `/admin/aparencia`
- [ ] Layout com nav tabs funcional
- [ ] Logout limpa sessão
- [ ] Rotas `/admin/*` bloqueadas por `AuthGate`

**CRUD:**
- [ ] Marcas, Unidades, Preços, Fotos, Extras têm CRUD funcional
- [ ] Reservas read-only com filtros
- [ ] Todas as queries filtradas por tenant

**Deploy:**
- [ ] Vercel publicado
- [ ] Wildcard domain funcionando
- [ ] 2 tenants de teste subindo com identidades diferentes

---

## Ordem de execução sugerida

1. **Parte A** (schema) — base de tudo, roda primeiro
2. **Parte B** (auth) — pré-requisito pro admin
3. **Parte C** (tenant resolver + theming) — já faz a página pública usar config dinâmico, entrega valor imediato
4. **Parte D** (admin shell + Aparência) — você já consegue editar identidade
5. **Parte E** (demais abas CRUD) — uma por uma, testáveis independentemente
6. **Parte F** (deploy) — só no final, depois que tudo funcionar local

Se quiser fazer só parte dela agora (ex: Partes A + C pra ver a página pública virar genérica), é totalmente possível — cada parte é auto-contida.

## Próximas fases

- **Fase 5** — Polish visual (hero, animações framer-motion, carrossel, skeletons, success screen confetti)
- **Fase 6** — QA ponta-a-ponta + produção final
