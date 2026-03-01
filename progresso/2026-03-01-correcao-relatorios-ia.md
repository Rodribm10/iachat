# Nota de Progresso: Correção Relatórios IA (Captain Reports)

**Objetivo:** Corrigir as traduções e o comportamento visual/sincronização dos relatórios de IA do Capitão.

**Contexto:** Os relatórios não exibiam traduções corretas para períodos e inboxes devido a uma duplicação no `settings.json`. Além disso, a data exibia shift de timezone e não havia polling de status.

**Passos Realizados:**
1. Removida a duplicação de `CAPTAIN_REPORTS` no `settings.json` (PT e EN).
2. Centralizadas as traduções em `captain.json`.
3. Atualizado `InsightsController#index` para carregar todos os relatórios por padrão, permitindo visualizações imediatas.
4. Adicionado mecanismo de polling (10s) na UI para relatórios em processamento.
5. Corrigida a formatação de data para evitar mudança de dia por fuso horário.

**Arquivos Alterados:**
- `app/controllers/api/v1/accounts/captain/reports/insights_controller.rb`
- `app/javascript/dashboard/i18n/locale/en/captain.json`
- `app/javascript/dashboard/i18n/locale/en/settings.json`
- `app/javascript/dashboard/i18n/locale/pt_BR/captain.json`
- `app/javascript/dashboard/i18n/locale/pt_BR/integrations.json`
- `app/javascript/dashboard/i18n/locale/pt_BR/settings.json`
- `app/javascript/dashboard/routes/dashboard/settings/captain/reports/Index.vue`

**Como Validar:**
- Acesse Relatórios IA.
- Verifique se aparecem os relatórios existentes sem precisar selecionar filtros.
- Gere um novo relatório e acompanhe o status mudar de "Pendente/Processando" para "Concluído" sem atualizar a página.
- Verifique se a data exibida no card é idêntica à selecionada no filtro.
