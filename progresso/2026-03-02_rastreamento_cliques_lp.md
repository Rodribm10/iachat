# Rastreamento de Cliques da Landing Page

### Objetivo
Garantir que os cliques na landing page sejam rastreados, capturando UTMs (origem, campanha) e vinculando-os aos contatos no Chatwoot.

### Contexto
Atualmente, o `TrackingController` e o `LeadClick` capturam o hostname e o IP, mas não estão salvando o `click_id` (enviado pelo frontend) nem extraindo parâmetros UTM da URL da landing page.

### Como testar:
Na tela de chat, conferir se os Atributos `lp`, `campanha`, `origem` e `click_id` estão sendo preenchidos para novos contatos do WhatsApp criados através de LPs.

## Parte 2 - Multiunidade (Server-side LPs)
- **Problema:** As Landing Pages dependiam do `localStorage` do navegador para manter configurações (nº de telefone, titulo, etc). Isso tornava impossível rastreamento persistente (quando o usuário trocava de celular) e não suportava estrutura multiunidade profissional.
- **Implementação:**
  1. Feita migração adicionando à tabela `landing_hosts` os campos faltantes: `initial_message`, `default_source`, `default_campanha`, `custom_config`.
  2. Atualizamos `LandingPagesController` (Controller Backend) para carregar os dados baseando-se no `request.host`.
  3. Modificamos o HTML de exibição principal (`app/views/public/landing_pages/show.html.erb`), removendo painel de administração overlay e substituindo por ERB para renderização Server-Side (SSG).

## Em Andamento / Concluídos Recentes
1. **Backend**: Atualizar o `TrackingController` para salvar `click_id` e extrair UTMs caso não sejam enviados explicitamente.
2. Validar se o `click_id` está sendo recebido no Controller corretamente (testado via postman/local e aprovado - os testes do Sidekiq estão rodando no log).
3. Criar painel no Dashboard para gerenciar `landing_hosts` (migrando configurações do front-end armazenadas no LocalStorage para Back-end em estrutura multi-unidade) -> **Concluído:** Criada interface em Inboxes > Configurações > Landing Pages.

### Próximos Passos
1. **Migração**: Adicionar o campo `click_id` na tabela `lead_clicks`.
3. **Frontend**: Sugerir script JS para a landing page que capture UTMs da URL e as envie para o Supabase.
- Adicionar interface "Painel Admin" para Gerenciar Landing Pages dentro das configurações originais do Chatwoot (Vue Frontend).
- Conferir os Logs de tracking e Sidekiq em mensagens locais para debugar qualquer problema residual no `AttributionMatcherService`.

### Como Validar
Simular um clique com UTMs:
```bash
curl -X POST http://localhost:3000/track/click \
  -H "Content-Type: application/json" \
  -d '{"hostname": "teste.com", "click_id": "123", "lp": "https://teste.com/?utm_source=meta&utm_campaign=blackfriday"}'
```
Verificar se o contato criado posteriormente recebe as atribuições `link_de_origem` e `campanha`.
