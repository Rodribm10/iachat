# Adicionando Cores aos Status de Reserava

**Objetivo:** Alterar a exibição em texto simples dos status das reservas (Rascunho, Confirmada, etc.) para tags visuais coloridas, facilitando a visualização rápida pelos capitães.

**Contexto:** O componente UI de listagem de reservas (`Index.vue`) e o componente de resumo na barra lateral das conversas (`ReservationSummary.vue`) exibiam o `status_label` com um fundo cinza genérico para todos os status.

**Passos:**
1. Criada uma função `statusColor` que mapeia o campo `ui_status` do backend para classes CSS dinâmicas baseadas nas cores já disponíveis da paleta atual (Tailwind - `bg-n-...`).
2. Atualizado o `Index.vue` na visualização tipo Lista (Tabela) para injetar essas classes de cor correspondente.
3. Atualizado o `ReservationSummary.vue` (barra lateral do chat) para usar a mesma lógica no Computed property `statusColor`.

**Principais Arquivos Alterados:**
- [app/javascript/dashboard/routes/dashboard/captain/reservations/Index.vue](file:///Users/user/Dev/Produtos/Chatwoot-fazer-ai/fazer-ai-kanban/chatwoot/app/javascript/dashboard/routes/dashboard/captain/reservations/Index.vue)
- [app/javascript/dashboard/routes/dashboard/conversation/reservation/ReservationSummary.vue](file:///Users/user/Dev/Produtos/Chatwoot-fazer-ai/fazer-ai-kanban/chatwoot/app/javascript/dashboard/routes/dashboard/conversation/reservation/ReservationSummary.vue)

**Como Validar:**
1. Acesse o painel web local (ex: `localhost:3001`).
2. Vá até o menu de Reservas (Captain).
3. Na visualização de "Lista", verifique se a coluna "Status" tem diferentes cores, como ex. cinza para Draft, verde para Confirmada, e amarelo para Aguardando Pagamento.
4. Abra uma conversa que tenha uma reserva vinculada e veja se na barra lateral direita se o badge "Status" também aparece colorido de forma coerente com o `ui_status`.

**Como Reverter:**
As classes customizadas dinâmicas podem ser removidas revertendo o commit correspondente nestes arquivos, voltando assim o uso estático de `class="bg-n-surface-2 text-n-slate-12"` em ambos os templates do span.
