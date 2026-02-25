# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a **Chatwoot** customer engagement platform (open-source alternative to Intercom/Zendesk), customized for **fazer.ai**. It includes the **Synkra AIOS** framework overlay for AI-orchestrated development workflows.

**Tech Stack:**
- Backend: Ruby 3.4.4 + Rails 7.1
- Frontend: Vue 3 + Vite
- Database: PostgreSQL with pgvector
- Background Jobs: Sidekiq
- Package Manager: **pnpm** (required, not npm/yarn)
- Testing: RSpec (backend), Vitest (frontend)

## Development Commands

### Starting the Application

```bash
# Development server (Rails backend + Sidekiq + Vite)
pnpm run dev

# Individual processes:
# - Rails backend: http://localhost:3001
# - Sidekiq: background worker
# - Vite: frontend dev server
```

### Testing

```bash
# Frontend (Vitest) - CRITICAL: NO -- flag with pnpm test!
pnpm test                    # Run all tests
pnpm test <file>             # Run specific file (NOT pnpm test -- <file>)
pnpm test:watch              # Watch mode
pnpm test:coverage           # Coverage report

# Backend (RSpec)
bundle exec rspec                           # All specs
bundle exec rspec spec/models/user_spec.rb  # Specific file
bundle exec rspec spec/models/user_spec.rb:42  # Specific line
```

### Code Quality

```bash
# JavaScript/Vue linting
pnpm run eslint              # Check
pnpm run eslint:fix          # Auto-fix

# Ruby linting
bundle exec rubocop          # Check
bundle exec rubocop -a       # Auto-fix
pnpm run ruby:prettier       # Same as rubocop -a
```

### Database

```bash
bin/rails db:migrate
bin/rails db:rollback
bin/rails db:reset
bin/rails db:seed
```

## Architecture Overview

### Backend Structure

```
app/
├── controllers/       # API endpoints (API::V1::Accounts::*)
├── models/            # ActiveRecord models
├── services/          # Business logic (Whatsapp::Providers::*, etc.)
├── jobs/              # Sidekiq background jobs
├── listeners/         # Wisper event subscribers (pub/sub)
├── builders/          # Complex object construction
├── finders/           # Query objects
├── policies/          # Pundit authorization
└── javascript/        # Vue.js frontend

enterprise/app/        # Enterprise features (Captain AI, billing)
```

**Key Patterns:**
- **Services:** Business logic extracted from models
- **Builders:** Construct complex objects
- **Finders:** Encapsulate complex queries
- **Listeners:** Event-driven using Wisper
- **Policies:** Pundit for authorization
- **Jobs:** All async work in Sidekiq

### Frontend Structure

```
app/javascript/
├── dashboard/         # Agent dashboard (Vue 3 + Vue Router + Vuex)
│   ├── routes/       # Page components
│   ├── store/        # Vuex state
│   ├── components/   # Reusable components
│   ├── api/          # API clients
│   └── i18n/         # Translations (en, pt_BR required!)
├── widget/           # Customer chat widget
├── sdk/              # Embeddable JavaScript SDK
├── portal/           # Public help center
└── shared/           # Shared utilities
```

**Vite Import Aliases:**
- `components` → `app/javascript/dashboard/components`
- `dashboard` → `app/javascript/dashboard`
- `helpers` → `app/javascript/shared/helpers`
- `shared`, `widget`, `survey`, `v3` → respective directories

## Critical Conventions

### fazer.ai Branding
**ALWAYS** style as `fazer.ai` (lowercase with dot), **NEVER** `Fazer.ai` or `FAZER.AI`

### Internationalization
**ALWAYS include pt_BR translations** for any new user-facing text
- Location: `app/javascript/dashboard/i18n/locale/{en,pt_BR}/`

### Testing Philosophy
- Add specs when modifying code (use judgment)
- Test behavior, not implementation
- Consider cross-stack impacts (backend ↔ frontend)

---

# AIOS Framework Integration

This repository includes **Synkra AIOS** - an AI-orchestrated development system.

<!-- AIOS-MANAGED-START: core -->
## Core Rules

1. Siga a Constitution em `.aios-core/constitution.md`
2. Priorize `CLI First -> Observability Second -> UI Third`
3. Trabalhe por stories em `docs/stories/`
4. Nao invente requisitos fora dos artefatos existentes
<!-- AIOS-MANAGED-END: core -->

<!-- AIOS-MANAGED-START: quality -->
## Quality Gates

- Rode `npm run lint`
- Rode `npm run typecheck`
- Rode `npm test`
- Atualize checklist e file list da story antes de concluir
<!-- AIOS-MANAGED-END: quality -->

<!-- AIOS-MANAGED-START: codebase -->
## Project Map

- Core framework: `.aios-core/`
- CLI entrypoints: `bin/`
- Shared packages: `packages/`
- Tests: `tests/`
- Docs: `docs/`
<!-- AIOS-MANAGED-END: codebase -->

<!-- AIOS-MANAGED-START: commands -->
## Common Commands

- `npm run sync:ide`
- `npm run sync:ide:check`
- `npm run sync:skills:codex`
- `npm run sync:skills:codex:global` (opcional; neste repo o padrao e local-first)
- `npm run validate:structure`
- `npm run validate:agents`
<!-- AIOS-MANAGED-END: commands -->

<!-- AIOS-MANAGED-START: shortcuts -->
## Agent Shortcuts

Preferencia de ativacao no Codex CLI:
1. Use `/skills` e selecione `aios-<agent-id>` vindo de `.codex/skills` (ex.: `aios-architect`)
2. Se preferir, use os atalhos abaixo (`@architect`, `/architect`, etc.)

Interprete os atalhos abaixo carregando o arquivo correspondente em `.aios-core/development/agents/` (fallback: `.codex/agents/`), renderize o greeting via `generate-greeting.js` e assuma a persona ate `*exit`:

- `@architect`, `/architect`, `/architect.md` -> `.aios-core/development/agents/architect.md`
- `@dev`, `/dev`, `/dev.md` -> `.aios-core/development/agents/dev.md`
- `@qa`, `/qa`, `/qa.md` -> `.aios-core/development/agents/qa.md`
- `@pm`, `/pm`, `/pm.md` -> `.aios-core/development/agents/pm.md`
- `@po`, `/po`, `/po.md` -> `.aios-core/development/agents/po.md`
- `@sm`, `/sm`, `/sm.md` -> `.aios-core/development/agents/sm.md`
- `@analyst`, `/analyst`, `/analyst.md` -> `.aios-core/development/agents/analyst.md`
- `@devops`, `/devops`, `/devops.md` -> `.aios-core/development/agents/devops.md`
- `@data-engineer`, `/data-engineer`, `/data-engineer.md` -> `.aios-core/development/agents/data-engineer.md`
- `@ux-design-expert`, `/ux-design-expert`, `/ux-design-expert.md` -> `.aios-core/development/agents/ux-design-expert.md`
- `@squad-creator`, `/squad-creator`, `/squad-creator.md` -> `.aios-core/development/agents/squad-creator.md`
- `@aios-master`, `/aios-master`, `/aios-master.md` -> `.aios-core/development/agents/aios-master.md`
<!-- AIOS-MANAGED-END: shortcuts -->
