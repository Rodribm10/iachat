# Reserva Rede 1001 — Fase 1: Fundação (Plano de Implementação)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Criar o novo projeto `reserva-1001` do zero como Vite + React 19 + TypeScript + Tailwind v4 + Supabase, com a paleta premium aplicada, schema novo no Supabase, e uma página de teste renderizando marcas reais do banco.

**Architecture:** App Vite novo em `/Users/user/Dev/Produtos/Chatwoot-fazer-ai/fazer-ai-kanban/reserva-1001/`, separado do Chatwoot. POC antigo fica como `_poc-reference/` para consulta. Reutiliza o schema `reserva_hotel` existente no projeto Supabase `acdvblhzzaneddlxqyst` (InAudit Hotel), com migração aditiva para fotos, extras e integração Chatwoot. Nenhuma integração com Chatwoot ainda — isso é Fase 2.

**Tech Stack:** Vite 6 · React 19 · TypeScript 5.6 · Tailwind v4 · shadcn/ui (cva + Radix) · Supabase JS 2 · framer-motion 12 · anime.js 4 · Vitest · ESLint · Prettier

**Spec:** `docs/superpowers/specs/2026-04-13-reserva-1001-design.md`

**Escopo desta fase:** somente fundação. Sem fluxo de reserva, sem checkout, sem admin funcional, sem animações avançadas. A entrega é: "app compila, roda, mostra marcas vindas do Supabase com paleta premium aplicada".

---

## Pré-requisitos (já resolvidos)

**Supabase:** projeto **InAudit Hotel** (`acdvblhzzaneddlxqyst`), schema **`reserva_hotel`** reaproveitado. Migration aditiva (3 tabelas novas: `fotos_categoria`, `extras`, `reserva_extras` + colunas `chatwoot_*`) já aplicada via MCP antes de iniciar o plano.

**Credenciais:**
- URL: `https://acdvblhzzaneddlxqyst.supabase.co`
- Anon key: ver `.env.local` (criado na Task 4)
- Schema: `reserva_hotel`

**Tabelas PT-BR disponíveis:**
`marcas`, `unidades`, `suites`, `suites_unidades`, `precos`, `contas_pagamento`, `reservas`, `fotos_categoria`, `extras`, `reserva_extras`, `vw_precos_completa`, `vw_reservas_completa`.

**⚠️ Ação manual do usuário necessária:** no Supabase Dashboard → Project Settings → API → **Data API settings** → **Exposed schemas**, adicionar `reserva_hotel` à lista (se ainda não estiver). Sem isso, o cliente JS não consegue ler as tabelas.

**Ferramental local (já validado):** Node v20, pnpm 9.14, supabase CLI 2.48.

---

## File Structure

Estrutura final ao fim da Fase 1:

```
reserva-1001/
├── .env.local                    # credenciais (gitignored)
├── .env.local.example            # template
├── .gitignore
├── .prettierrc
├── README.md
├── eslint.config.js
├── index.html                    # sem importmap esm.sh
├── package.json
├── pnpm-lock.yaml
├── tsconfig.json
├── tsconfig.app.json
├── tsconfig.node.json
├── vite.config.ts
├── _poc-reference/               # POC antigo, só pra consulta
│   └── hotel-1001-noites-prime---reserva/
├── supabase/
│   ├── config.toml
│   └── migrations/
│       └── 20260413000001_reserva_1001_additive_schema.sql
└── src/
    ├── main.tsx                  # entrypoint
    ├── App.tsx                   # shell simples exibindo marcas
    ├── index.css                 # tokens Tailwind v4 + paleta premium
    ├── lib/
    │   ├── supabase.ts           # cliente Supabase
    │   └── utils.ts              # cn() helper (clsx + tailwind-merge)
    ├── components/
    │   ├── FormField.tsx         # migrado do POC, adaptado à paleta
    │   ├── SelectField.tsx       # migrado do POC, adaptado à paleta
    │   └── ui/
    │       └── button.tsx        # shadcn/ui Button base
    ├── types/
    │   └── database.ts           # gerado via supabase gen types
    └── __tests__/
        └── App.test.tsx          # smoke test Vitest
```

---

## Task 1: Preparar o diretório (mover POC pra referência, iniciar git)

**Files:**
- Modify: `reserva-1001/` (estrutura)
- Create: `reserva-1001/.gitignore`

- [ ] **Step 1: Mover o POC pra subpasta de referência**

```bash
cd /Users/user/Dev/Produtos/Chatwoot-fazer-ai/fazer-ai-kanban/reserva-1001
mkdir -p _poc-reference
mv hotel-1001-noites-prime---reserva _poc-reference/
ls -la
```

Expected: agora `reserva-1001/` contém só `_poc-reference/`.

- [ ] **Step 2: Inicializar git e criar .gitignore**

```bash
cd /Users/user/Dev/Produtos/Chatwoot-fazer-ai/fazer-ai-kanban/reserva-1001
git init
```

Create `.gitignore`:
```
# Dependencies
node_modules/
.pnp
.pnp.js

# Build
dist/
build/
*.tsbuildinfo

# Env
.env
.env.local
.env.*.local

# Editor
.vscode/
.idea/
*.swp
.DS_Store

# Logs
npm-debug.log*
pnpm-debug.log*
yarn-debug.log*

# Test coverage
coverage/

# Supabase
supabase/.branches
supabase/.temp
```

- [ ] **Step 3: Primeiro commit (só o POC de referência e gitignore)**

```bash
cd /Users/user/Dev/Produtos/Chatwoot-fazer-ai/fazer-ai-kanban/reserva-1001
git add .gitignore _poc-reference/
git commit -m "chore: inicializa repo com POC como referencia"
```

---

## Task 2: Scaffold do projeto Vite + React + TypeScript

**Files:**
- Create: `reserva-1001/package.json`
- Create: `reserva-1001/vite.config.ts`
- Create: `reserva-1001/tsconfig.json`
- Create: `reserva-1001/tsconfig.node.json`
- Create: `reserva-1001/index.html`
- Create: `reserva-1001/src/main.tsx`
- Create: `reserva-1001/src/App.tsx`

- [ ] **Step 1: Criar package.json manualmente (evita o prompt interativo do create-vite)**

Create `reserva-1001/package.json`:
```json
{
  "name": "reserva-1001",
  "private": true,
  "version": "0.1.0",
  "type": "module",
  "scripts": {
    "dev": "vite",
    "build": "tsc -b && vite build",
    "preview": "vite preview",
    "lint": "eslint .",
    "format": "prettier --write .",
    "test": "vitest run",
    "test:watch": "vitest",
    "typecheck": "tsc --noEmit",
    "supabase:types": "supabase gen types typescript --local > src/types/database.ts"
  },
  "dependencies": {
    "@radix-ui/react-slot": "^1.1.0",
    "@supabase/supabase-js": "^2.45.0",
    "animejs": "^4.0.2",
    "class-variance-authority": "^0.7.0",
    "clsx": "^2.1.1",
    "lucide-react": "^0.454.0",
    "motion": "^12.4.0",
    "react": "^19.1.0",
    "react-dom": "^19.1.0",
    "tailwind-merge": "^2.5.0"
  },
  "devDependencies": {
    "@tailwindcss/vite": "^4.0.0",
    "@testing-library/jest-dom": "^6.5.0",
    "@testing-library/react": "^16.0.0",
    "@types/node": "^22.9.0",
    "@types/react": "^19.0.0",
    "@types/react-dom": "^19.0.0",
    "@vitejs/plugin-react": "^5.0.0",
    "eslint": "^9.14.0",
    "eslint-config-prettier": "^9.1.0",
    "eslint-plugin-react-hooks": "^5.0.0",
    "eslint-plugin-react-refresh": "^0.4.14",
    "globals": "^15.12.0",
    "jsdom": "^25.0.1",
    "prettier": "^3.3.3",
    "tailwindcss": "^4.0.0",
    "typescript": "^5.6.3",
    "typescript-eslint": "^8.14.0",
    "vite": "^6.0.0",
    "vitest": "^2.1.5"
  }
}
```

- [ ] **Step 2: Criar tsconfig.json**

Create `reserva-1001/tsconfig.json`:
```json
{
  "files": [],
  "references": [
    { "path": "./tsconfig.app.json" },
    { "path": "./tsconfig.node.json" }
  ],
  "compilerOptions": {
    "skipLibCheck": true
  }
}
```

Create `reserva-1001/tsconfig.app.json`:
```json
{
  "compilerOptions": {
    "target": "ES2022",
    "useDefineForClassFields": true,
    "lib": ["ES2022", "DOM", "DOM.Iterable"],
    "module": "ESNext",
    "skipLibCheck": true,
    "moduleResolution": "bundler",
    "allowImportingTsExtensions": true,
    "isolatedModules": true,
    "moduleDetection": "force",
    "noEmit": true,
    "jsx": "react-jsx",
    "strict": true,
    "noUnusedLocals": true,
    "noUnusedParameters": true,
    "noFallthroughCasesInSwitch": true,
    "baseUrl": ".",
    "paths": {
      "@/*": ["./src/*"]
    },
    "types": ["vitest/globals", "@testing-library/jest-dom"]
  },
  "include": ["src"]
}
```

Create `reserva-1001/tsconfig.node.json`:
```json
{
  "compilerOptions": {
    "target": "ES2022",
    "lib": ["ES2023"],
    "module": "ESNext",
    "skipLibCheck": true,
    "moduleResolution": "bundler",
    "allowSyntheticDefaultImports": true,
    "strict": true,
    "noEmit": true,
    "types": ["node"]
  },
  "include": ["vite.config.ts"]
}
```

- [ ] **Step 3: Criar vite.config.ts com alias @ e Tailwind v4 plugin**

Create `reserva-1001/vite.config.ts`:
```ts
import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import tailwindcss from '@tailwindcss/vite'
import path from 'node:path'

export default defineConfig({
  plugins: [react(), tailwindcss()],
  resolve: {
    alias: {
      '@': path.resolve(__dirname, './src'),
    },
  },
  test: {
    environment: 'jsdom',
    globals: true,
    setupFiles: './src/__tests__/setup.ts',
  },
})
```

- [ ] **Step 4: Criar index.html limpo (sem importmap esm.sh)**

Create `reserva-1001/index.html`:
```html
<!doctype html>
<html lang="pt-BR">
  <head>
    <meta charset="UTF-8" />
    <link rel="icon" type="image/svg+xml" href="/vite.svg" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>Reserva Rede 1001</title>
    <link rel="preconnect" href="https://fonts.googleapis.com" />
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin />
    <link
      href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700;800&family=Fraunces:opsz,wght@9..144,300;9..144,500;9..144,700&display=swap"
      rel="stylesheet"
    />
  </head>
  <body>
    <div id="root"></div>
    <script type="module" src="/src/main.tsx"></script>
  </body>
</html>
```

- [ ] **Step 5: Criar src/main.tsx**

Create `reserva-1001/src/main.tsx`:
```tsx
import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import './index.css'
import App from './App'

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <App />
  </StrictMode>
)
```

- [ ] **Step 6: Criar src/App.tsx placeholder**

Create `reserva-1001/src/App.tsx`:
```tsx
export default function App() {
  return (
    <div className="min-h-screen bg-obsidian text-ivory flex items-center justify-center">
      <h1 className="font-serif text-5xl text-champagne">Reserva Rede 1001</h1>
    </div>
  )
}
```

- [ ] **Step 7: Instalar dependências**

```bash
cd /Users/user/Dev/Produtos/Chatwoot-fazer-ai/fazer-ai-kanban/reserva-1001
pnpm install
```

Expected: instala sem erros. Gera `pnpm-lock.yaml`.

- [ ] **Step 8: Commit**

```bash
git add package.json pnpm-lock.yaml tsconfig*.json vite.config.ts index.html src/main.tsx src/App.tsx
git commit -m "feat: scaffold inicial do projeto vite + react + typescript"
```

Nota: ainda vai dar erro no build porque `index.css` não existe — resolvido na Task 3.

---

## Task 3: Configurar Tailwind v4 com paleta premium

**Files:**
- Create: `reserva-1001/src/index.css`

- [ ] **Step 1: Criar src/index.css com tokens do Tailwind v4 e paleta premium**

Create `reserva-1001/src/index.css`:
```css
@import 'tailwindcss';

@theme {
  /* Paleta premium Reserva 1001 */
  --color-obsidian: #0b0d12;
  --color-midnight: #0f1a2e;
  --color-champagne: #c9a961;
  --color-rose-gold: #e8b4a0;
  --color-ivory: #f5f1e8;
  --color-slate: #6b7280;
  --color-emerald: #10b981;
  --color-ruby: #e11d48;

  /* Tipografia */
  --font-sans: 'Inter', system-ui, sans-serif;
  --font-serif: 'Fraunces', Georgia, serif;

  /* Raios */
  --radius-lg: 0.75rem;
  --radius-xl: 1rem;
  --radius-2xl: 1.5rem;
}

@layer base {
  html,
  body {
    height: 100%;
    margin: 0;
    font-family: var(--font-sans);
    -webkit-font-smoothing: antialiased;
    -moz-osx-font-smoothing: grayscale;
  }

  body {
    background: linear-gradient(180deg, var(--color-obsidian) 0%, var(--color-midnight) 100%);
    color: var(--color-ivory);
  }

  h1,
  h2,
  h3 {
    font-family: var(--font-serif);
    letter-spacing: -0.02em;
  }
}

@layer utilities {
  .text-gradient-gold {
    background: linear-gradient(135deg, var(--color-champagne), var(--color-rose-gold));
    -webkit-background-clip: text;
    background-clip: text;
    -webkit-text-fill-color: transparent;
  }

  .glow-champagne {
    box-shadow: 0 0 30px rgba(201, 169, 97, 0.4);
  }
}
```

- [ ] **Step 2: Rodar o dev server pra validar visualmente**

```bash
cd /Users/user/Dev/Produtos/Chatwoot-fazer-ai/fazer-ai-kanban/reserva-1001
pnpm dev
```

Expected: abre em `http://localhost:5173`, mostra "Reserva Rede 1001" em Fraunces dourado (champagne) sobre fundo escuro com gradiente obsidian→midnight.

Pare o server com `Ctrl+C` depois de validar.

- [ ] **Step 3: Commit**

```bash
git add src/index.css
git commit -m "feat: configura tailwind v4 com paleta premium (obsidian/champagne/rose-gold)"
```

---

## Task 4: Setup do cliente Supabase + variáveis de ambiente

**Files:**
- Create: `reserva-1001/.env.local`
- Create: `reserva-1001/.env.local.example`
- Create: `reserva-1001/src/lib/supabase.ts`
- Create: `reserva-1001/src/lib/utils.ts`
- Create: `reserva-1001/src/types/database.ts` (placeholder inicial)

- [ ] **Step 1: Criar .env.local.example (template commitado)**

Create `reserva-1001/.env.local.example`:
```
# Supabase — projeto InAudit Hotel
VITE_SUPABASE_URL=https://acdvblhzzaneddlxqyst.supabase.co
VITE_SUPABASE_ANON_KEY=
VITE_SUPABASE_SCHEMA=reserva_hotel

# Chatwoot — token de integração (Fase 2)
VITE_CHATWOOT_API_URL=https://chatwoot.fazer.ai
VITE_CHATWOOT_API_TOKEN=
```

- [ ] **Step 2: Criar .env.local com as credenciais reais do projeto InAudit Hotel**

Create `reserva-1001/.env.local`:
```
VITE_SUPABASE_URL=https://acdvblhzzaneddlxqyst.supabase.co
VITE_SUPABASE_ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImFjZHZibGh6emFuZWRkbHhxeXN0Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTA4MTMyNzcsImV4cCI6MjA2NjM4OTI3N30.wwmr0TMYuds-QLrTESR4kx34umssseDyEsPjVRt02qI
VITE_SUPABASE_SCHEMA=reserva_hotel
VITE_CHATWOOT_API_URL=https://chatwoot.fazer.ai
VITE_CHATWOOT_API_TOKEN=
```

**IMPORTANTE:** este arquivo está no `.gitignore` e NÃO vai pro git.

- [ ] **Step 3: Criar src/lib/utils.ts (cn helper)**

Create `reserva-1001/src/lib/utils.ts`:
```ts
import { clsx, type ClassValue } from 'clsx'
import { twMerge } from 'tailwind-merge'

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs))
}
```

- [ ] **Step 4: Criar src/types/database.ts inicial (vazio — será regenerado na Task 6)**

Create `reserva-1001/src/types/database.ts`:
```ts
// Este arquivo é gerado automaticamente via `pnpm supabase:types`.
// Não edite à mão. Regenerar após cada migration.

export type Json = string | number | boolean | null | { [key: string]: Json | undefined } | Json[]

export type Database = {
  public: {
    Tables: Record<string, never>
    Views: Record<string, never>
    Functions: Record<string, never>
    Enums: Record<string, never>
    CompositeTypes: Record<string, never>
  }
}
```

- [ ] **Step 5: Criar src/lib/supabase.ts**

Create `reserva-1001/src/lib/supabase.ts`:
```ts
import { createClient } from '@supabase/supabase-js'
import type { Database } from '@/types/database'

const supabaseUrl = import.meta.env.VITE_SUPABASE_URL
const supabaseAnonKey = import.meta.env.VITE_SUPABASE_ANON_KEY
const supabaseSchema = import.meta.env.VITE_SUPABASE_SCHEMA ?? 'reserva_hotel'

if (!supabaseUrl || !supabaseAnonKey) {
  throw new Error(
    'Variáveis VITE_SUPABASE_URL e VITE_SUPABASE_ANON_KEY não estão definidas. Copie .env.local.example para .env.local e preencha.'
  )
}

export const supabase = createClient<Database>(supabaseUrl, supabaseAnonKey, {
  db: { schema: supabaseSchema as 'reserva_hotel' },
})
```

- [ ] **Step 6: Validar que o typecheck passa**

```bash
cd /Users/user/Dev/Produtos/Chatwoot-fazer-ai/fazer-ai-kanban/reserva-1001
pnpm typecheck
```

Expected: sem erros.

- [ ] **Step 7: Commit**

```bash
git add .env.local.example src/lib/supabase.ts src/lib/utils.ts src/types/database.ts
git commit -m "feat: configura cliente supabase com variaveis de ambiente"
```

---

## Task 5: Documentar a migration aditiva (schema já aplicado via MCP)

**Contexto:** A migration aditiva ao schema `reserva_hotel` já foi aplicada no projeto Supabase antes do plano começar (via MCP). Esta task **só cria o arquivo SQL** como fonte de verdade/histórico no repositório — **não roda `supabase db push`**.

**Files:**
- Create: `reserva-1001/supabase/config.toml` (via CLI)
- Create: `reserva-1001/supabase/migrations/20260413000001_reserva_1001_additive_schema.sql`

- [ ] **Step 1: Inicializar Supabase CLI no projeto**

```bash
cd /Users/user/Dev/Produtos/Chatwoot-fazer-ai/fazer-ai-kanban/reserva-1001
supabase init
```

Expected: cria `supabase/config.toml` e `supabase/` folder. Se perguntar sobre VSCode settings, responda N.

- [ ] **Step 2: Criar o arquivo de migration (DDL da migration já aplicada)**

Create `reserva-1001/supabase/migrations/20260413000001_reserva_1001_additive_schema.sql`:
```sql
-- Reserva Rede 1001 — adições ao schema reserva_hotel existente
-- Já aplicada via MCP. Este arquivo é a fonte de verdade histórica.
-- Zero alteração destrutiva. Tudo aditivo.

-- === 1. Fotos por categoria de suíte (linked por unidade + nome da categoria) ===
create table if not exists reserva_hotel.fotos_categoria (
  id          uuid primary key default gen_random_uuid(),
  id_unidade  uuid not null references reserva_hotel.unidades(id) on delete cascade,
  categoria   text not null,
  url_foto    text not null,
  alt         text,
  ordem       int not null default 0,
  ativa       boolean not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create index if not exists idx_fotos_categoria_unidade on reserva_hotel.fotos_categoria(id_unidade);
create index if not exists idx_fotos_categoria_lookup on reserva_hotel.fotos_categoria(id_unidade, categoria);

-- === 2. Extras (adicionais por marca) ===
create table if not exists reserva_hotel.extras (
  id           uuid primary key default gen_random_uuid(),
  id_marca     uuid not null references reserva_hotel.marcas(id) on delete cascade,
  titulo       text not null,
  descricao    text,
  preco        numeric not null check (preco >= 0),
  imagem_url   text,
  ativo        boolean not null default true,
  ordem        int not null default 0,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

create index if not exists idx_extras_marca on reserva_hotel.extras(id_marca);

-- === 3. Junction reserva ↔ extras ===
create table if not exists reserva_hotel.reserva_extras (
  id_reserva   uuid not null references reserva_hotel.reservas(id) on delete cascade,
  id_extra     uuid not null references reserva_hotel.extras(id),
  preco        numeric not null check (preco >= 0),
  created_at   timestamptz not null default now(),
  primary key (id_reserva, id_extra)
);

-- === 4. Integração Chatwoot em unidades ===
alter table reserva_hotel.unidades
  add column if not exists chatwoot_unit_id bigint;

create index if not exists idx_unidades_chatwoot_unit on reserva_hotel.unidades(chatwoot_unit_id);

-- === 5. Integração Chatwoot em reservas ===
alter table reserva_hotel.reservas
  add column if not exists chatwoot_contact_id bigint;

alter table reserva_hotel.reservas
  add column if not exists chatwoot_conversation_id bigint;

alter table reserva_hotel.reservas
  add column if not exists chatwoot_pix_charge_id bigint;

create index if not exists idx_reservas_chatwoot_conversation on reserva_hotel.reservas(chatwoot_conversation_id);
create index if not exists idx_reservas_txid_pix on reserva_hotel.reservas(txid_pix);
```

- [ ] **Step 3: Commit**

Nota: não há seed.sql neste plano — o schema `reserva_hotel` já contém 1 marca de seed e o usuário vai cadastrar o resto via admin (Fase 4). Também não rodamos `supabase db push` porque a migration já foi aplicada via MCP antes do plano.

```bash
git add supabase/config.toml supabase/migrations/
git commit -m "feat: documenta migration aditiva do schema reserva_hotel"
```

---

## Task 6: Gerar types TypeScript do schema reserva_hotel

**Files:**
- Modify: `reserva-1001/src/types/database.ts`

- [ ] **Step 1: Linkar CLI ao projeto InAudit Hotel**

```bash
cd /Users/user/Dev/Produtos/Chatwoot-fazer-ai/fazer-ai-kanban/reserva-1001
supabase link --project-ref acdvblhzzaneddlxqyst
```

Vai pedir a senha do banco. Use a senha do projeto. Se não souber, peça pro usuário.

- [ ] **Step 2: Gerar os tipos do schema reserva_hotel**

```bash
supabase gen types typescript --linked --schema reserva_hotel > src/types/database.ts
```

Expected: `src/types/database.ts` contém `Database` tipado com as tabelas `marcas`, `unidades`, `suites`, `precos`, `reservas`, `fotos_categoria`, `extras`, `reserva_extras`, `contas_pagamento` sob o namespace `reserva_hotel`.

**Nota:** o cliente Supabase configurado em Task 4 já aponta para o schema `reserva_hotel` via `db: { schema }`. Logo, ao fazer `supabase.from('marcas')`, ele automaticamente resolve `reserva_hotel.marcas`.

- [ ] **Step 3: Validar typecheck**

```bash
pnpm typecheck
```

Expected: passa sem erros.

- [ ] **Step 4: Atualizar o script `supabase:types` em package.json**

Edit `reserva-1001/package.json`, campo `scripts`:

De:
```json
"supabase:types": "supabase gen types typescript --local > src/types/database.ts"
```

Para:
```json
"supabase:types": "supabase gen types typescript --linked --schema reserva_hotel > src/types/database.ts"
```

- [ ] **Step 5: Commit**

```bash
git add src/types/database.ts package.json
git commit -m "feat: gera tipos typescript do schema reserva_hotel"
```

---

## Task 7: Renderizar marcas reais no App.tsx

**Files:**
- Modify: `reserva-1001/src/App.tsx`

- [ ] **Step 1: Reescrever App.tsx para buscar e exibir marcas do Supabase (schema reserva_hotel, tabela `marcas`)**

Replace `reserva-1001/src/App.tsx`:
```tsx
import { useEffect, useState } from 'react'
import { supabase } from '@/lib/supabase'
import type { Database } from '@/types/database'

type Marca = Database['reserva_hotel']['Tables']['marcas']['Row']

export default function App() {
  const [marcas, setMarcas] = useState<Marca[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    async function loadMarcas() {
      const { data, error } = await supabase
        .from('marcas')
        .select('*')
        .eq('ativa', true)
        .order('nome', { ascending: true })

      if (error) {
        setError(error.message)
      } else {
        setMarcas(data ?? [])
      }
      setLoading(false)
    }
    loadMarcas()
  }, [])

  return (
    <main className="min-h-screen flex flex-col items-center justify-center px-6 py-12">
      <header className="text-center mb-12">
        <p className="font-sans text-sm uppercase tracking-[0.3em] text-rose-gold mb-4">
          Experiência exclusiva
        </p>
        <h1 className="font-serif text-6xl md:text-7xl text-gradient-gold mb-4">
          Reserva Rede 1001
        </h1>
        <p className="font-sans text-slate text-lg">Escolha uma das nossas marcas para começar</p>
      </header>

      {loading && <p className="text-slate">Carregando marcas...</p>}

      {error && (
        <div className="rounded-xl border border-ruby/40 bg-ruby/10 p-4 text-ivory">
          Erro ao carregar: {error}
        </div>
      )}

      {!loading && !error && marcas.length === 0 && (
        <p className="text-slate">Nenhuma marca cadastrada ainda.</p>
      )}

      {!loading && !error && marcas.length > 0 && (
        <ul className="grid grid-cols-1 md:grid-cols-2 gap-4 w-full max-w-2xl">
          {marcas.map((marca) => (
            <li
              key={marca.id}
              className="rounded-xl border border-champagne/20 bg-midnight/60 backdrop-blur p-6 text-center transition hover:border-champagne hover:glow-champagne"
            >
              <h2 className="font-serif text-2xl text-champagne">{marca.nome}</h2>
              {marca.descricao && <p className="text-slate text-sm mt-1">{marca.descricao}</p>}
              {marca.categorias && marca.categorias.length > 0 && (
                <p className="text-rose-gold text-xs mt-2 uppercase tracking-widest">
                  {marca.categorias.join(' · ')}
                </p>
              )}
            </li>
          ))}
        </ul>
      )}

      <footer className="mt-16 text-slate text-xs uppercase tracking-widest">
        © 2026 Reserva Rede 1001 · Fase 1 · Fundação
      </footer>
    </main>
  )
}
```

- [ ] **Step 2: Validar visualmente no browser**

```bash
pnpm dev
```

Abra `http://localhost:5173`. Expected: vê as marcas existentes no schema `reserva_hotel` (hoje 1 marca: "Hotel 1001 Noites") em cards escuros com borda dourada sutil, título "Reserva Rede 1001" em gradiente dourado. Hover nos cards faz a borda brilhar.

Pare com `Ctrl+C`.

- [ ] **Step 3: Commit**

```bash
git add src/App.tsx
git commit -m "feat: renderiza marcas reais do supabase na pagina inicial"
```

---

## Task 8: Migrar FormField e SelectField do POC com paleta premium

**Files:**
- Create: `reserva-1001/src/components/FormField.tsx`
- Create: `reserva-1001/src/components/SelectField.tsx`

- [ ] **Step 1: Ler os componentes do POC como referência**

```bash
cat _poc-reference/hotel-1001-noites-prime---reserva/components/FormField.tsx
cat _poc-reference/hotel-1001-noites-prime---reserva/components/SelectField.tsx
```

- [ ] **Step 2: Criar FormField.tsx adaptado à nova paleta**

Create `reserva-1001/src/components/FormField.tsx`:
```tsx
import { forwardRef, type InputHTMLAttributes } from 'react'
import { cn } from '@/lib/utils'

interface FormFieldProps extends InputHTMLAttributes<HTMLInputElement> {
  label: string
  error?: string
  required?: boolean
}

export const FormField = forwardRef<HTMLInputElement, FormFieldProps>(
  ({ label, error, required, className, id, ...props }, ref) => {
    const inputId = id ?? `field-${label.toLowerCase().replace(/\s+/g, '-')}`

    return (
      <div className="flex flex-col gap-2">
        <label
          htmlFor={inputId}
          className="font-sans text-xs uppercase tracking-widest text-champagne"
        >
          {label}
          {required && <span className="text-rose-gold ml-1">*</span>}
        </label>
        <input
          ref={ref}
          id={inputId}
          aria-invalid={error ? 'true' : 'false'}
          className={cn(
            'w-full rounded-lg border border-champagne/30 bg-midnight/60 px-4 py-3',
            'font-sans text-ivory placeholder:text-slate',
            'focus:outline-none focus:border-champagne focus:glow-champagne',
            'transition-all duration-200',
            error && 'border-ruby focus:border-ruby',
            className
          )}
          {...props}
        />
        {error && <span className="text-ruby text-xs font-sans">{error}</span>}
      </div>
    )
  }
)

FormField.displayName = 'FormField'
```

- [ ] **Step 3: Criar SelectField.tsx adaptado à nova paleta**

Create `reserva-1001/src/components/SelectField.tsx`:
```tsx
import { forwardRef, type SelectHTMLAttributes } from 'react'
import { ChevronDown } from 'lucide-react'
import { cn } from '@/lib/utils'

interface Option {
  value: string
  label: string
}

interface SelectFieldProps extends Omit<SelectHTMLAttributes<HTMLSelectElement>, 'children'> {
  label: string
  options: Option[]
  placeholder?: string
  error?: string
  required?: boolean
}

export const SelectField = forwardRef<HTMLSelectElement, SelectFieldProps>(
  (
    { label, options, placeholder = 'Selecione...', error, required, className, id, ...props },
    ref
  ) => {
    const selectId = id ?? `select-${label.toLowerCase().replace(/\s+/g, '-')}`

    return (
      <div className="flex flex-col gap-2">
        <label
          htmlFor={selectId}
          className="font-sans text-xs uppercase tracking-widest text-champagne"
        >
          {label}
          {required && <span className="text-rose-gold ml-1">*</span>}
        </label>
        <div className="relative">
          <select
            ref={ref}
            id={selectId}
            aria-invalid={error ? 'true' : 'false'}
            className={cn(
              'w-full appearance-none rounded-lg border border-champagne/30 bg-midnight/60 px-4 py-3 pr-10',
              'font-sans text-ivory',
              'focus:outline-none focus:border-champagne focus:glow-champagne',
              'transition-all duration-200',
              error && 'border-ruby focus:border-ruby',
              className
            )}
            {...props}
          >
            <option value="" disabled>
              {placeholder}
            </option>
            {options.map((opt) => (
              <option key={opt.value} value={opt.value} className="bg-midnight text-ivory">
                {opt.label}
              </option>
            ))}
          </select>
          <ChevronDown
            aria-hidden
            className="pointer-events-none absolute right-3 top-1/2 -translate-y-1/2 h-4 w-4 text-champagne"
          />
        </div>
        {error && <span className="text-ruby text-xs font-sans">{error}</span>}
      </div>
    )
  }
)

SelectField.displayName = 'SelectField'
```

- [ ] **Step 4: Validar typecheck**

```bash
pnpm typecheck
```

Expected: passa.

- [ ] **Step 5: Commit**

```bash
git add src/components/FormField.tsx src/components/SelectField.tsx
git commit -m "feat: migra FormField e SelectField com paleta premium"
```

---

## Task 9: Criar componente Button base (shadcn/ui style)

**Files:**
- Create: `reserva-1001/src/components/ui/button.tsx`

- [ ] **Step 1: Criar Button com cva e variantes premium**

Create `reserva-1001/src/components/ui/button.tsx`:
```tsx
import { forwardRef, type ButtonHTMLAttributes } from 'react'
import { Slot } from '@radix-ui/react-slot'
import { cva, type VariantProps } from 'class-variance-authority'
import { cn } from '@/lib/utils'

const buttonVariants = cva(
  'inline-flex items-center justify-center gap-2 rounded-lg font-sans font-semibold transition-all duration-200 disabled:pointer-events-none disabled:opacity-50 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-champagne/60',
  {
    variants: {
      variant: {
        primary:
          'bg-gradient-to-r from-champagne to-rose-gold text-obsidian hover:glow-champagne hover:scale-[1.02]',
        secondary:
          'border border-champagne/30 bg-midnight/60 text-ivory hover:border-champagne hover:glow-champagne',
        ghost: 'text-champagne hover:bg-champagne/10',
        destructive: 'bg-ruby text-ivory hover:bg-ruby/90',
      },
      size: {
        sm: 'h-9 px-4 text-sm',
        md: 'h-11 px-6 text-base',
        lg: 'h-14 px-8 text-lg',
      },
    },
    defaultVariants: {
      variant: 'primary',
      size: 'md',
    },
  }
)

interface ButtonProps
  extends ButtonHTMLAttributes<HTMLButtonElement>,
    VariantProps<typeof buttonVariants> {
  asChild?: boolean
}

export const Button = forwardRef<HTMLButtonElement, ButtonProps>(
  ({ className, variant, size, asChild = false, ...props }, ref) => {
    const Comp = asChild ? Slot : 'button'
    return (
      <Comp className={cn(buttonVariants({ variant, size }), className)} ref={ref} {...props} />
    )
  }
)

Button.displayName = 'Button'

export { buttonVariants }
```

- [ ] **Step 2: Validar typecheck**

```bash
pnpm typecheck
```

Expected: passa.

- [ ] **Step 3: Commit**

```bash
git add src/components/ui/button.tsx
git commit -m "feat: componente Button base com variantes premium"
```

---

## Task 10: Configurar Vitest + setup file + smoke test

**Files:**
- Create: `reserva-1001/src/__tests__/setup.ts`
- Create: `reserva-1001/src/__tests__/App.test.tsx`

- [ ] **Step 1: Criar setup file do Vitest**

Create `reserva-1001/src/__tests__/setup.ts`:
```ts
import '@testing-library/jest-dom/vitest'
import { cleanup } from '@testing-library/react'
import { afterEach, vi } from 'vitest'

afterEach(() => {
  cleanup()
})

// Mock do Supabase client — imita from('marcas').select('*').eq('ativa', true).order('nome')
vi.mock('@/lib/supabase', () => {
  const mockMarcas = [
    {
      id: '3fac5ed4-100f-4c0a-82ce-06110758b9c9',
      nome: 'Hotel 1001 Noites',
      categorias: ['Standard', 'Superior', 'Luxo'],
      permanencias: ['3hrs', '6hrs', 'Pernoite'],
      descricao: null,
      ativa: true,
      created_at: '2026-04-13T00:00:00Z',
      updated_at: '2026-04-13T00:00:00Z',
    },
    {
      id: '11111111-1111-1111-1111-111111111111',
      nome: 'Dolce Amore',
      categorias: ['Suite Master', 'Apartamento'],
      permanencias: ['3hrs', '4hrs'],
      descricao: null,
      ativa: true,
      created_at: '2026-04-13T00:00:00Z',
      updated_at: '2026-04-13T00:00:00Z',
    },
  ]

  const orderFn = vi.fn(() => Promise.resolve({ data: mockMarcas, error: null }))
  const eqFn = vi.fn(() => ({ order: orderFn }))
  const selectFn = vi.fn(() => ({ eq: eqFn, order: orderFn }))
  const fromFn = vi.fn(() => ({ select: selectFn }))

  return {
    supabase: { from: fromFn },
  }
})
```

- [ ] **Step 2: Escrever smoke test do App.tsx (TDD: test primeiro)**

Create `reserva-1001/src/__tests__/App.test.tsx`:
```tsx
import { render, screen, waitFor } from '@testing-library/react'
import { describe, it, expect } from 'vitest'
import App from '@/App'

describe('App', () => {
  it('renderiza título premium', () => {
    render(<App />)
    expect(screen.getByRole('heading', { name: /reserva rede 1001/i })).toBeInTheDocument()
  })

  it('exibe marcas retornadas do supabase após carregar', async () => {
    render(<App />)
    await waitFor(() => {
      expect(screen.getByText('Hotel 1001 Noites')).toBeInTheDocument()
      expect(screen.getByText('Dolce Amore')).toBeInTheDocument()
    })
  })

  it('não mostra estado de loading após fetch completar', async () => {
    render(<App />)
    await waitFor(() => {
      expect(screen.queryByText(/carregando marcas/i)).not.toBeInTheDocument()
    })
  })
})
```

- [ ] **Step 3: Rodar os testes**

```bash
cd /Users/user/Dev/Produtos/Chatwoot-fazer-ai/fazer-ai-kanban/reserva-1001
pnpm test
```

Expected: 3 testes passando. Se não, o App.tsx já foi escrito na Task 7 de forma a passar — provavelmente só um ajuste no mock.

- [ ] **Step 4: Commit**

```bash
git add src/__tests__/
git commit -m "test: smoke test do App com mock do supabase"
```

---

## Task 11: Configurar ESLint + Prettier

**Files:**
- Create: `reserva-1001/eslint.config.js`
- Create: `reserva-1001/.prettierrc`
- Create: `reserva-1001/.prettierignore`

- [ ] **Step 1: Criar eslint.config.js (flat config)**

Create `reserva-1001/eslint.config.js`:
```js
import js from '@eslint/js'
import globals from 'globals'
import reactHooks from 'eslint-plugin-react-hooks'
import reactRefresh from 'eslint-plugin-react-refresh'
import tseslint from 'typescript-eslint'
import prettier from 'eslint-config-prettier'

export default tseslint.config(
  { ignores: ['dist', '_poc-reference', 'supabase'] },
  {
    extends: [js.configs.recommended, ...tseslint.configs.recommended, prettier],
    files: ['**/*.{ts,tsx}'],
    languageOptions: {
      ecmaVersion: 2022,
      globals: globals.browser,
    },
    plugins: {
      'react-hooks': reactHooks,
      'react-refresh': reactRefresh,
    },
    rules: {
      ...reactHooks.configs.recommended.rules,
      'react-refresh/only-export-components': ['warn', { allowConstantExport: true }],
      '@typescript-eslint/no-unused-vars': ['error', { argsIgnorePattern: '^_' }],
    },
  }
)
```

- [ ] **Step 2: Instalar dependências faltantes do ESLint**

```bash
cd /Users/user/Dev/Produtos/Chatwoot-fazer-ai/fazer-ai-kanban/reserva-1001
pnpm add -D @eslint/js
```

- [ ] **Step 3: Criar .prettierrc**

Create `reserva-1001/.prettierrc`:
```json
{
  "semi": false,
  "singleQuote": true,
  "trailingComma": "es5",
  "printWidth": 100,
  "tabWidth": 2,
  "arrowParens": "always",
  "endOfLine": "lf"
}
```

- [ ] **Step 4: Criar .prettierignore**

Create `reserva-1001/.prettierignore`:
```
dist
node_modules
_poc-reference
supabase/.branches
supabase/.temp
pnpm-lock.yaml
```

- [ ] **Step 5: Rodar lint e format**

```bash
pnpm lint
pnpm format
```

Expected: lint passa sem erros. Prettier formata os arquivos.

- [ ] **Step 6: Commit**

```bash
git add eslint.config.js .prettierrc .prettierignore package.json pnpm-lock.yaml src/
git commit -m "chore: configura eslint flat config + prettier"
```

---

## Task 12: Criar README do projeto

**Files:**
- Create: `reserva-1001/README.md`

- [ ] **Step 1: Escrever README**

Create `reserva-1001/README.md`:
```markdown
# Reserva Rede 1001

Página pública de reserva para as marcas do Grupo Nova (Hotel 1001 Noites, Prime, Express, Dolce Amore).

**Status:** Fase 1 — Fundação

## Stack

- Vite 6 + React 19 + TypeScript
- Tailwind v4 com paleta premium (obsidian/champagne/rose-gold)
- Supabase (Postgres + Auth + Storage)
- framer-motion + anime.js
- Vitest + Testing Library

## Setup local

1. Instale as dependências:
   ```bash
   pnpm install
   ```

2. Copie as variáveis de ambiente:
   ```bash
   cp .env.local.example .env.local
   ```
   Preencha `VITE_SUPABASE_URL` e `VITE_SUPABASE_ANON_KEY` com os dados do seu projeto Supabase.

3. Rode o dev server:
   ```bash
   pnpm dev
   ```
   Abre em `http://localhost:5173`.

## Comandos

| Comando | Descrição |
|---|---|
| `pnpm dev` | Dev server com HMR |
| `pnpm build` | Build de produção |
| `pnpm preview` | Preview do build |
| `pnpm lint` | Roda ESLint |
| `pnpm format` | Formata com Prettier |
| `pnpm test` | Roda testes (Vitest) |
| `pnpm test:watch` | Testes em watch mode |
| `pnpm typecheck` | TypeScript check |
| `pnpm supabase:types` | Regenera tipos do Supabase |

## Estrutura

```
src/
├── components/    # Componentes React
│   └── ui/        # Primitivos shadcn/ui
├── lib/           # Clientes (supabase) e utils
├── types/         # Tipos gerados do Supabase
└── __tests__/     # Testes Vitest
supabase/
└── migrations/    # SQL de schema (source of truth)
_poc-reference/    # POC antigo — só pra consultar
```

## Paleta premium

| Token | Hex | Uso |
|---|---|---|
| `obsidian` | `#0B0D12` | Fundo principal |
| `midnight` | `#0F1A2E` | Superfícies elevadas |
| `champagne` | `#C9A961` | Ação primária, luxo |
| `rose-gold` | `#E8B4A0` | Acento secundário |
| `ivory` | `#F5F1E8` | Texto principal |
| `slate` | `#6B7280` | Texto secundário |
| `emerald` | `#10B981` | Sucesso |
| `ruby` | `#E11D48` | Erro |

## Integração com Chatwoot

Esta fase **não** integra com Chatwoot ainda. A geração de PIX acontece na Fase 2, onde um endpoint novo é criado no Chatwoot (`POST /public/api/v1/captain/public_reservations`) e esta app passa a consumir.

## Referências

- Spec de design: `chatwoot/docs/superpowers/specs/2026-04-13-reserva-1001-design.md`
- Plano Fase 1: `chatwoot/docs/superpowers/plans/2026-04-13-reserva-1001-fase-1-fundacao.md`
```

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs: adiciona README da fase 1"
```

---

## Task 13: Validação final — rodar tudo e conferir

- [ ] **Step 1: Typecheck**

```bash
cd /Users/user/Dev/Produtos/Chatwoot-fazer-ai/fazer-ai-kanban/reserva-1001
pnpm typecheck
```

Expected: sem erros.

- [ ] **Step 2: Lint**

```bash
pnpm lint
```

Expected: sem erros.

- [ ] **Step 3: Testes**

```bash
pnpm test
```

Expected: 3 testes passando.

- [ ] **Step 4: Build**

```bash
pnpm build
```

Expected: build sem erros, gera `dist/`.

- [ ] **Step 5: Dev server + inspeção visual**

```bash
pnpm dev
```

Abra `http://localhost:5173`:
- Título "Reserva Rede 1001" em gradiente dourado ✓
- Marcas do schema `reserva_hotel` listadas em cards escuros com borda champagne ✓
- Hover nos cards faz borda brilhar ✓
- Fundo com gradiente obsidian→midnight ✓
- Fonte serif (Fraunces) nos títulos, sans (Inter) no resto ✓

Pare com `Ctrl+C`.

- [ ] **Step 6: git log pra conferir a trilha de commits**

```bash
git log --oneline
```

Expected: algo parecido com:
```
abc1234 docs: adiciona README da fase 1
bcd2345 chore: configura eslint flat config + prettier
cde3456 test: smoke test do App com mock do supabase
def4567 feat: componente Button base com variantes premium
efg5678 feat: migra FormField e SelectField com paleta premium
fgh6789 feat: renderiza marcas reais do supabase na pagina inicial
ghi7890 feat: gera tipos typescript do supabase
hij8901 feat: documenta migration aditiva do schema reserva_hotel
ijk9012 feat: configura cliente supabase com variaveis de ambiente
jkl0123 feat: configura tailwind v4 com paleta premium (obsidian/champagne/rose-gold)
klm1234 feat: scaffold inicial do projeto vite + react + typescript
lmn2345 chore: inicializa repo com POC como referencia
```

---

## Critérios de conclusão da Fase 1

- [ ] `pnpm typecheck`, `pnpm lint`, `pnpm test`, `pnpm build` todos passam
- [ ] Dev server sobe e renderiza a página inicial com as marcas vindas do schema `reserva_hotel`
- [ ] Paleta premium visível e consistente
- [ ] Tipografia Fraunces + Inter carregada
- [ ] FormField, SelectField e Button prontos para uso (mesmo que não usados ainda)
- [ ] Schema Supabase aplicado e tipos gerados
- [ ] README funcional
- [ ] Commits atômicos e descritivos

## Próxima fase

**Fase 2 — Backend Chatwoot:** criar o controller `PublicReservationsController` no repo do Chatwoot com os endpoints `POST /public_reservations` e `GET /public_reservations/:id/status`, com token auth e testes RSpec. Plano separado: `docs/superpowers/plans/2026-04-13-reserva-1001-fase-2-backend-chatwoot.md` (a escrever).
