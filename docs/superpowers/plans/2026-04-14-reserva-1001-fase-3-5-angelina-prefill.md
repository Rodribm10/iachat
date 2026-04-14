# Reserva Rede 1001 — Fase 3.5: Angelina preenche + fechamento Fase 2+3

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task.

**Goal:** A atendente de IA do Chatwoot (Angelina) conversa com o cliente no WhatsApp, coleta os dados da reserva, e envia um link da página `reserva-1001` já preenchida. Cliente só clica "Confirmar e Pagar". Também fecha lacunas da Fase 2+3 (label `aguardando_pagamento`).

**Architecture:** Query params na URL (Opção A — MVP). Nova ferramenta Captain `GenerateReservationLink` que monta o URL a partir do contexto da conversa. Frontend reserva-1001 lê os params no boot via `URLSearchParams` e seed a o hook `useReservationForm`.

**Tech Stack:** Rails 7 (nova ferramenta Captain) · React 19 + Vite (prefill logic) · Chatwoot Captain tools infra

**Spec pai:** `docs/superpowers/specs/2026-04-13-reserva-1001-design.md`
**Fase anterior:** `docs/superpowers/plans/2026-04-13-reserva-1001-fase-2-3-fluxo-completo.md` ✅

---

## Dados conhecidos

- `Captain::Tools::GeneratePix` em `enterprise/app/services/captain/tools/generate_pix_tool.rb` — referência de tool. Usa `BaseTool` (investigar assinatura).
- `Captain::Unit` id=4 = Hotel 1001 Águas Lindas, inbox 2, tem Inter PIX configurado.
- Assistente "Angelina" existe no Chatwoot, vinculado a alguma account. Precisa verificar qual e como adicionar uma tool a ela.
- `mark_conversation_as_awaiting_payment` do GeneratePix (linhas 713-721) é o padrão canonical de label:
  ```ruby
  current = conversation.label_list
  merged  = (current + ['aguardando_pagamento']).uniq
  merged -= %w[pagamento_confirmado reserva_feita]
  conversation.update_labels(merged)
  ```

---

## File Structure

**Backend (Chatwoot):**
```
enterprise/app/controllers/public/api/v1/captain/
└── public_reservations_controller.rb           # modify (add label helper)

enterprise/app/services/captain/tools/
└── generate_reservation_link_tool.rb           # novo

config/                                          # possivelmente novo seed/script pra registrar tool no assistant

spec/enterprise/services/captain/tools/
└── generate_reservation_link_tool_spec.rb      # novo (opcional mas ideal)
```

**Frontend (reserva-1001):**
```
src/lib/
└── prefill.ts                                  # novo — parse query params

src/hooks/
└── useReservationForm.ts                       # modify — aceita initial state

src/App.tsx                                     # modify — passa prefill pro hook
```

---

## Pré-requisitos

1. Chatwoot dev rodando em `:3000`
2. reserva-1001 dev rodando em `:5180`
3. Identificar o `assistant_id` do Angelina (via SQL ou UI do Captain)

---

## Task 1: Fix do label `aguardando_pagamento` no controller (fechamento Fase 2+3)

**Files:**
- Modify: `chatwoot/app/controllers/public/api/v1/captain/public_reservations_controller.rb`

- [ ] **Step 1: Adicionar helper + chamada**

No método `create`, depois de criar a Reservation e ANTES de chamar CobService (ou depois, tanto faz — o importante é que aconteça), adicionar chamada ao helper. E no `private:` adicionar o método.

Edit no `create`, logo após `reservation = Captain::Reservation.create!(...)`:
```ruby
    mark_conversation_as_awaiting_payment(conversation)
```

E adicionar no bloco `private`:
```ruby
  def mark_conversation_as_awaiting_payment(conversation)
    current = conversation.label_list
    merged  = (current + ['aguardando_pagamento']).uniq
    merged -= %w[pagamento_confirmado reserva_feita]
    conversation.update_labels(merged)
  rescue StandardError => e
    Rails.logger.error("[PublicReservations] label update failed: #{e.message}")
    # Não falha a request por causa disso
  end
```

- [ ] **Step 2: Smoke test**

```bash
curl -s -o /tmp/r.json -w "HTTP %{http_code}\n" -X POST http://localhost:3000/public/api/v1/captain/public_reservations \
  -H "Content-Type: application/json" \
  -H "X-Reserva-Token: dev-token-change-in-prod" \
  -d '{
    "chatwoot_unit_id": 4,
    "category": "Standard",
    "stay_type": "3hrs",
    "checkin_at": "2026-04-14T18:00:00Z",
    "customer": {"name":"Teste Label","phone":"+5561999997777","cpf":"12345678909","email":"t@l.com"},
    "total_cents": 12000,
    "deposit_cents": 6000
  }'
```

Expected: HTTP 201. Depois, via SQL, confirmar que a conversa tem label `aguardando_pagamento`:
```bash
PGPASSWORD= psql -h localhost -U postgres -d chatwoot_dev -c \
  "SELECT id, additional_attributes FROM conversations ORDER BY id DESC LIMIT 3;"
```

Ou via `conversation.label_list` no console Rails.

- [ ] **Step 3: Commit**

```bash
cd /Users/user/Dev/Produtos/Chatwoot-fazer-ai/fazer-ai-kanban/chatwoot
git add app/controllers/public/api/v1/captain/public_reservations_controller.rb
git commit -m "feat: adiciona label aguardando_pagamento ao criar reserva (fecha fase 2+3)"
```

---

## Task 2: Frontend — parser de query params

**Files:**
- Create: `reserva-1001/src/lib/prefill.ts`

- [ ] **Step 1: Criar o parser**

Create `reserva-1001/src/lib/prefill.ts`:
```ts
import type { ReservationFormState } from '@/hooks/useReservationForm'

// Mapeamento dos query params para o estado do form.
// marca/unidade/categoria/permanencia vêm como NOMES (string), não IDs —
// a UI resolve os IDs depois que o catálogo carrega (ver Task 3).
export interface PrefillData {
  marcaNome?: string
  unidadeNome?: string
  permanencia?: string
  categoria?: string
  checkinAt?: string // ISO
  nome?: string
  telefone?: string
  cpf?: string
  email?: string
  observacao?: string
}

export function parsePrefillFromURL(): PrefillData {
  if (typeof window === 'undefined') return {}
  const params = new URLSearchParams(window.location.search)

  const get = (key: string) => params.get(key)?.trim() || undefined

  return {
    marcaNome: get('marca'),
    unidadeNome: get('unidade'),
    permanencia: get('permanencia'),
    categoria: get('categoria'),
    checkinAt: get('checkin'),
    nome: get('nome'),
    telefone: get('telefone'),
    cpf: get('cpf'),
    email: get('email'),
    observacao: get('obs'),
  }
}

// Converte PrefillData em atualizações pontuais no form.
// Retorna apenas os campos "simples" (não dependentes de resolução de catálogo).
export function prefillSimpleFields(prefill: PrefillData): Partial<ReservationFormState> {
  const out: Partial<ReservationFormState> = {}
  if (prefill.nome) out.nome = prefill.nome
  if (prefill.telefone) out.telefone = prefill.telefone
  if (prefill.cpf) out.cpf = prefill.cpf
  if (prefill.email) out.email = prefill.email
  if (prefill.observacao) out.observacao = prefill.observacao
  if (prefill.checkinAt) {
    // Converte ISO para datetime-local format (yyyy-MM-ddThh:mm)
    try {
      const d = new Date(prefill.checkinAt)
      if (!isNaN(d.getTime())) {
        const pad = (n: number) => String(n).padStart(2, '0')
        out.checkinAt = `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`
      }
    } catch {
      // ignore
    }
  }
  return out
}
```

- [ ] **Step 2: Typecheck + commit**

```bash
cd /Users/user/Dev/Produtos/Chatwoot-fazer-ai/fazer-ai-kanban/reserva-1001
pnpm typecheck
git add src/lib/prefill.ts
git commit -m "feat: parser de query params para prefill do formulario"
```

---

## Task 3: Hook — suporte a prefill em cascata

**Files:**
- Modify: `reserva-1001/src/hooks/useReservationForm.ts`

- [ ] **Step 1: Adicionar lógica de resolução**

O hook já tem effects em cascata que carregam marcas/unidades quando marcaId/unidadeId mudam. Precisamos:
1. Aceitar `prefill: PrefillData` como argumento opcional
2. Quando `marcas` carregar, resolver `marcaNome` → `marcaId` e aplicar
3. Quando `unidades` carregar (depois da marca), resolver `unidadeNome` → `unidadeId`
4. Depois disso, setar `categoria` e `permanencia` direto (são strings, não IDs)
5. Aplicar os campos simples (nome, tel, etc) no estado inicial

Substituir o início do hook para aceitar `initialPrefill` e processar a resolução assim que as listas carregarem. Mostrar apenas as mudanças (o resto do hook fica igual):

No topo do arquivo, importar:
```ts
import type { PrefillData } from '@/lib/prefill'
import { prefillSimpleFields } from '@/lib/prefill'
```

Mudar a assinatura:
```ts
export function useReservationForm(initialPrefill?: PrefillData) {
```

Mudar o estado inicial:
```ts
  const [form, setForm] = useState<ReservationFormState>(() => ({
    ...empty,
    ...prefillSimpleFields(initialPrefill ?? {}),
  }))
```

Adicionar um ref de "já aplicou prefill de marca/unidade/categoria/permanencia" pra não reaplicar:
```ts
  const appliedPrefillRef = useRef(false)
```
(e `import { useRef } from 'react'` no topo)

Adicionar um `useEffect` novo que roda quando marcas carregam, faz o match por nome, chama `update('marcaId', ...)` e guarda as strings de categoria/permanencia pra aplicar depois:
```ts
  useEffect(() => {
    if (appliedPrefillRef.current) return
    if (!initialPrefill?.marcaNome) return
    if (marcas.length === 0) return

    const marca = marcas.find(
      (m) => m.nome.toLowerCase() === initialPrefill.marcaNome!.toLowerCase()
    )
    if (marca) {
      setForm((prev) => ({ ...prev, marcaId: marca.id }))
    }
  }, [marcas, initialPrefill])
```

Outro effect que roda quando unidades carregam (depende de marcaId):
```ts
  useEffect(() => {
    if (appliedPrefillRef.current) return
    if (!initialPrefill?.unidadeNome) return
    if (unidades.length === 0) return

    const unidade = unidades.find(
      (u) => u.nome.toLowerCase() === initialPrefill.unidadeNome!.toLowerCase()
    )
    if (unidade) {
      setForm((prev) => ({
        ...prev,
        unidadeId: unidade.id,
        permanencia: initialPrefill.permanencia ?? prev.permanencia,
        categoria: initialPrefill.categoria ?? prev.categoria,
      }))
      appliedPrefillRef.current = true
    }
  }, [unidades, initialPrefill])
```

- [ ] **Step 2: Typecheck + test**

```bash
cd /Users/user/Dev/Produtos/Chatwoot-fazer-ai/fazer-ai-kanban/reserva-1001
pnpm typecheck
pnpm test
```

Os 2 testes existentes do App devem continuar passando (o hook é mockado).

- [ ] **Step 3: Commit**

```bash
git add src/hooks/useReservationForm.ts
git commit -m "feat: useReservationForm aceita prefill e resolve nomes em cascata"
```

---

## Task 4: App.tsx — passa o prefill pro hook

**Files:**
- Modify: `reserva-1001/src/App.tsx` (na verdade, o ReservationFlow)
- Modify: `reserva-1001/src/components/reservation/ReservationFlow.tsx`

- [ ] **Step 1: Capturar prefill no boot**

Edit `src/components/reservation/ReservationFlow.tsx`:

No topo, importar:
```ts
import { parsePrefillFromURL } from '@/lib/prefill'
```

Criar uma constante MODULE-LEVEL (fora do componente) pra capturar o prefill UMA vez no boot — evita re-parse em cada render:
```ts
const initialPrefill = parsePrefillFromURL()
```

Mudar a chamada do hook:
```ts
const {
  form,
  update,
  ...
} = useReservationForm(initialPrefill)
```

- [ ] **Step 2: Rodar tudo**

```bash
pnpm typecheck
pnpm test
pnpm build
```

- [ ] **Step 3: Teste manual no navegador**

Abrir:
```
http://localhost:5180/?marca=Hotel%201001%20Noites&unidade=Hotel%201001%20%C3%81guas%20Lindas&permanencia=3hrs&categoria=Standard&checkin=2026-04-14T22:00:00Z&nome=Jo%C3%A3o%20Teste&telefone=61999998888&cpf=12345678909&email=joao@teste.com
```

Expected: ao carregar, marca já está selecionada, unidade também, permanência 3hrs, categoria Standard, data preenchida, nome/tel/cpf/email preenchidos. Só falta clicar "Confirmar e pagar".

- [ ] **Step 4: Commit**

```bash
git add src/components/reservation/ReservationFlow.tsx
git commit -m "feat: ReservationFlow aplica prefill de query params no boot"
```

---

## Task 5: Investigar infra de Captain Tools (antes de criar a nova tool)

**Files:** nenhum. É uma etapa de pesquisa.

- [ ] **Step 1: Mapear como ferramentas são registradas**

Ler os arquivos:
```bash
cd /Users/user/Dev/Produtos/Chatwoot-fazer-ai/fazer-ai-kanban/chatwoot
ls enterprise/app/services/captain/tools/
```

Entender:
- Qual a classe-base das tools (`BaseTool`? `Captain::Tools::Base`?)
- Como uma tool declara seu schema/parâmetros pro LLM
- Como ela é descoberta pelo assistant (registro explícito? autoload?)
- Como o assistant invoca a tool

Abrir `generate_pix_tool.rb` e identificar:
- Qual método é o entry point (`execute`?)
- Qual é a estrutura de retorno (`formatted_message`, `raw_payload`, `success`)
- Como ela pega o contexto da conversa (via `@conversation`?)

- [ ] **Step 2: Mapear o assistente Angelina no banco**

```bash
PGPASSWORD= psql -h localhost -U postgres -d chatwoot_dev -c \
  "SELECT id, name, account_id FROM captain_assistants ORDER BY id;"
```

Identificar o ID do assistente que representa a Angelina.

```bash
PGPASSWORD= psql -h localhost -U postgres -d chatwoot_dev -c \
  "SELECT id, assistant_id, title FROM captain_scenarios LIMIT 20;"
```

Ou investigar onde o assistente registra suas tools (pode ser em `tools`, `capabilities`, ou similar — checar o schema do `captain_assistants`).

- [ ] **Step 3: Documentar findings num arquivo temporário de notas**

Create `chatwoot/docs/superpowers/notes/angelina-tool-integration.md`:
```markdown
# Notas: integração de tool custom no assistente Angelina

## Classe-base das tools
<descrever>

## Como tools declaram schema
<descrever>

## Como tools são registradas num assistente
<descrever>

## Assistente Angelina
- ID: <X>
- Account ID: <Y>
- Tools atuais: <lista>
```

Commitar:
```bash
git add docs/superpowers/notes/angelina-tool-integration.md
git commit -m "docs: notas sobre integracao de tool custom na angelina"
```

---

## Task 6: Criar `GenerateReservationLinkTool`

**Files:**
- Create: `chatwoot/enterprise/app/services/captain/tools/generate_reservation_link_tool.rb`

- [ ] **Step 1: Criar o skeleton baseado no GeneratePixTool**

Copiar a assinatura básica do `GeneratePixTool` (herança de `BaseTool` ou equivalente descoberto na Task 5). A tool recebe params: `marca`, `unidade`, `permanencia`, `categoria`, `checkin_at`, `nome`, `telefone`, `cpf`, `email`, `observacao` (todos opcionais — a Angelina coleta o que consegue e manda).

Estrutura do arquivo:
```ruby
module Captain
  module Tools
    class GenerateReservationLinkTool < BaseTool  # ou a classe correta da Task 5
      DEFAULT_BASE_URL = 'http://localhost:5180'

      def name
        'generate_reservation_link'
      end

      def description
        <<~DESC
          Gera um link da página de reserva pública com os dados já pré-preenchidos.
          Use esta ferramenta quando já tiver coletado na conversa: marca, unidade,
          categoria da suíte, permanência, data/hora de check-in e dados do cliente
          (nome, telefone, CPF, email opcional). Envie o link retornado ao cliente
          para ele confirmar e pagar.
        DESC
      end

      def parameters_schema
        # Formato que a tool-base espera. Investigar na Task 5 se é JSON schema, hash simbolizado, etc.
        {
          type: 'object',
          properties: {
            marca: { type: 'string', description: 'Nome da marca (ex: Hotel 1001 Noites)' },
            unidade: { type: 'string', description: 'Nome da unidade do hotel' },
            permanencia: { type: 'string', description: 'Permanência escolhida (ex: 3hrs, 4hrs, Pernoite)' },
            categoria: { type: 'string', description: 'Categoria da suíte (ex: Standard, Hidromassagem)' },
            checkin_at: { type: 'string', description: 'Data e horário de check-in em ISO 8601' },
            nome: { type: 'string', description: 'Nome completo do cliente' },
            telefone: { type: 'string', description: 'Telefone do cliente' },
            cpf: { type: 'string', description: 'CPF do cliente (apenas números ou com formato)' },
            email: { type: 'string', description: 'Email do cliente (opcional)' },
            observacao: { type: 'string', description: 'Observação do cliente (opcional)' }
          },
          required: []
        }
      end

      def execute(*_args, **params)
        base = ENV.fetch('RESERVA_1001_BASE_URL', DEFAULT_BASE_URL)
        query = build_query(params)
        url = query.empty? ? base : "#{base}/?#{query}"

        {
          formatted_message: "Pronto! Clique no link para revisar e pagar a entrada via PIX:\n#{url}",
          url: url,
          success: true
        }
      end

      private

      def build_query(params)
        mapping = {
          marca: params[:marca],
          unidade: params[:unidade],
          permanencia: params[:permanencia],
          categoria: params[:categoria],
          checkin: params[:checkin_at],
          nome: params[:nome],
          telefone: params[:telefone],
          cpf: params[:cpf],
          email: params[:email],
          obs: params[:observacao]
        }
        URI.encode_www_form(mapping.compact.reject { |_, v| v.to_s.strip.empty? })
      end
    end
  end
end
```

**Nota:** a assinatura exata de `execute`, `name`, `description`, `parameters_schema` e a classe-base (`BaseTool`) devem vir da investigação da Task 5. Ajustar ali.

- [ ] **Step 2: Adicionar `RESERVA_1001_BASE_URL` no .env.example**

Edit `chatwoot/.env.example`, adicionar:
```
# Reserva Rede 1001 — URL base do app publico (usada pela Angelina pra gerar links prefill)
RESERVA_1001_BASE_URL=http://localhost:5180
```

Também adicionar ao `.env` local (não commitar).

- [ ] **Step 3: Commit**

```bash
git add enterprise/app/services/captain/tools/generate_reservation_link_tool.rb .env.example
git commit -m "feat: nova tool GenerateReservationLink para angelina enviar link prefill"
```

---

## Task 7: Registrar a tool no assistente Angelina

**Files:** depende da investigação da Task 5.

- [ ] **Step 1: Adicionar a tool ao assistente**

Via SQL direto ou UI do Captain:
- Via UI: abrir Settings → Captain → Assistants → Angelina → Tools → Add → `generate_reservation_link`
- Via SQL: investigar onde tools são registradas e fazer `UPDATE captain_assistants SET tools = tools || ...` ou criar row em tabela de junção

Registrar o comportamento:
```
A tool `generate_reservation_link` deve ser invocada quando o cliente já
informou: marca, unidade, categoria, permanência, data/hora, e ao menos
nome + telefone + CPF. O retorno da tool (a URL) deve ser enviado como
mensagem outgoing ao cliente.
```

- [ ] **Step 2: Teste manual — conversar com Angelina**

1. Abrir Chatwoot web
2. Entrar numa conversa com um contato de teste no inbox da Hotel 1001 Águas Lindas
3. Digitar como cliente (simulando): "Quero reservar uma suíte Standard na Águas Lindas, 3hrs, amanhã às 22h. Meu nome é João, CPF 123.456.789-09, telefone 61 99999 8888"
4. Angelina deve chamar a tool e devolver o link preenchido
5. Abrir o link numa aba nova — confirmar que tudo está preenchido
6. Só faltar clicar "Confirmar e pagar"

- [ ] **Step 3: Se algo não funcionar**

Iterar no prompt do assistente (system instructions) pra garantir que ele invoca a tool no momento certo. Isso é ajuste no Captain, não código.

---

## Critérios de conclusão

**Fechamento Fase 2+3:**
- [ ] Label `aguardando_pagamento` aparece na conversa após POST `/public_reservations`
- [ ] Após pagamento via webhook Inter, label é removida e `pagamento_confirmado` é adicionada (comportamento nativo do ConfirmationService)

**Fase 3.5 — Angelina prefill:**
- [ ] Abrir `http://localhost:5180/?marca=...&nome=...` mostra form já preenchido
- [ ] Angelina conversa com cliente, chama `GenerateReservationLink`, envia URL
- [ ] Cliente abre URL, vê tudo preenchido, clica "Confirmar e pagar", recebe PIX real

---

## Próximas fases (após esta)

- **Fase 4** — Admin CRUD (Supabase Auth + telas de cadastro)
- **Fase 5** — Polish visual (animações, hero, skeletons, confetti)
- **Fase 6** — Deploy Vercel + subdomínio

## Evolução possível (V2)

- Migrar de query params → token assinado (Opção B) quando o fluxo estiver validado
- Angelina também busca `unidades` e `categorias` via catálogo Supabase pra confirmar opções disponíveis (hoje ela envia os nomes que o cliente falou; se não bater, a página mostra vazio)
