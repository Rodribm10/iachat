# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Chatwoot** customizado para **fazer.ai** — plataforma de atendimento ao cliente multi-canal com IA (Captain). Multi-tenant SaaS para hotelaria, com integração de PIX/Inter, reservas e WhatsApp.

**Tech Stack:**
- Backend: Ruby 3.4.4 + Rails 7.1
- Frontend: Vue 3 + Vite + Pinia
- Database: PostgreSQL + pgvector
- Background Jobs: Sidekiq (com sidekiq-cron)
- Package Manager: **pnpm** (obrigatório — nunca npm/yarn)
- Testing: RSpec (backend), Vitest (frontend)
- Event system: Wisper (pub/sub)
- Authorization: Pundit

## Development Commands

### Iniciar aplicação

```bash
pnpm run dev           # overmind: Rails :3000 + Sidekiq + Vite
pnpm run start:dev     # foreman (alternativo)
```

### Testes

```bash
# Frontend (Vitest) — CRÍTICO: sem -- com pnpm!
pnpm test                      # todos
pnpm test app/javascript/path  # arquivo específico (NÃO use pnpm test -- <file>)
pnpm test:watch
pnpm test:coverage

# Backend (RSpec)
bundle exec rspec                                    # todos
bundle exec rspec spec/models/contact_spec.rb        # arquivo
bundle exec rspec spec/models/contact_spec.rb:42     # linha específica
```

### Qualidade de código

```bash
pnpm run eslint          # lint JS/Vue
pnpm run eslint:fix      # auto-fix
bundle exec rubocop      # lint Ruby
bundle exec rubocop -a   # auto-fix Ruby
```

### Database

```bash
bin/rails db:migrate
bin/rails db:rollback
bin/rails db:reset && bin/rails db:seed
```

### i18n

```bash
pnpm run sync:i18n       # sincroniza arquivo de tradução
```

## Arquitetura Backend

### Modelo de dados central

```
Account (tenant raiz)
  ├── Inbox (canal: WhatsApp, Email, Facebook, Instagram, Twilio...)
  │     └── Contact (cliente) via ContactInbox
  ├── Conversation (central: status, priority, SLA, custom_attributes)
  │     ├── Message (conteúdo, attachments, sender)
  │     ├── Agent (assignee)
  │     └── Label
  ├── AutomationRule
  ├── Campaign
  └── Article (help center)
```

### Padrões Rails usados

| Padrão | Onde | Função |
|--------|------|--------|
| **Services** | `app/services/` | Toda lógica de negócio fora dos models |
| **Builders** | `app/builders/` | Construção de objetos complexos (ex: criar conversa + contato) |
| **Finders** | `app/finders/` | Query objects encapsulados |
| **Listeners** | `app/listeners/` | Subscribers Wisper para eventos de domínio |
| **Policies** | `app/policies/` | Autorização Pundit por recurso |
| **Jobs** | `app/jobs/` | Todo trabalho assíncrono via Sidekiq |

### Estrutura de controllers

```
app/controllers/
├── api/v1/accounts/{account_id}/  # Endpoints principais (Conversations, Contacts, Inboxes...)
├── api/v1/widget/                 # Chat widget público
└── enterprise/api/v1/accounts/captain/  # Captain AI (enterprise)
```

### Enterprise — Captain AI (`enterprise/app/`)

Camada fazer.ai sobre o Chatwoot base:

- **Models chave:** `Captain::Unit` (multi-unidade hoteleira), `Captain::Assistant`, `Captain::Reservation`, `Captain::PixCharge`, `Captain::Document`, `Captain::ConversationInsight`
- **Integrações:** Inter API (pagamento PIX), WhatsApp, sincronização de reservas, webhooks
- **AI features:** LLM (OpenAI), copilot, audio transcription, label suggestion, help center search
- **Feature flags por account:** `captain_features` (Editor, Assistant, Copilot, LabelSuggestion, AudioTranscription, HelpCenterSearch)

## Arquitetura Frontend

```
app/javascript/
├── dashboard/         # Dashboard do agente (Vue 3 + Vue Router + Pinia)
│   ├── routes/        # Componentes de página
│   ├── store/         # Pinia stores (55+ módulos: conversations, contacts, captain*)
│   ├── components/    # Componentes reutilizáveis
│   ├── api/           # Clientes HTTP por recurso
│   └── i18n/locale/   # Traduções (en + pt_BR SEMPRE)
├── widget/            # Widget de chat embeddable
├── sdk/               # SDK JS (build separado: pnpm run build:sdk)
├── portal/            # Help center público
└── shared/            # Utilities compartilhados
```

**Aliases Vite:**
- `components` → `app/javascript/dashboard/components`
- `dashboard` → `app/javascript/dashboard`
- `helpers` → `app/javascript/shared/helpers`
- `shared`, `widget`, `survey`, `v3` → diretórios equivalentes

**Bibliotecas chave:** ProseMirror (rich text), ActionCable (real-time), Chart.js, Twilio Voice SDK

## Convenções críticas

### Branding
`fazer.ai` — sempre minúsculo com ponto. Nunca `Fazer.ai` ou `FAZER.AI`.

### Internacionalização
Qualquer texto visível ao usuário **exige** tradução em `en` e `pt_BR`:
```
app/javascript/dashboard/i18n/locale/en/
app/javascript/dashboard/i18n/locale/pt_BR/
```

### Novos canais / integrações
Siga o padrão existente em `app/services/whatsapp/` ou `app/services/instagram/` — nunca coloque lógica de canal no controller.

### Background jobs
Toda operação demorada vai para Sidekiq. Jobs em `app/jobs/`, enterprise em `enterprise/app/jobs/`.

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

- Rode `pnpm run eslint`
- Rode `bundle exec rubocop`
- Rode `pnpm test`
- Rode `bundle exec rspec`
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
