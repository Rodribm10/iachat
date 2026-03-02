# Rastreamento de Cliques da Landing Page

### Objetivo
Garantir que os cliques na landing page sejam rastreados, capturando UTMs (origem, campanha) e vinculando-os aos contatos no Chatwoot.

### Contexto
Atualmente, o `TrackingController` e o `LeadClick` capturam o hostname e o IP, mas não estão salvando o `click_id` (enviado pelo frontend) nem extraindo parâmetros UTM da URL da landing page.

### Próximos Passos
1. **Migração**: Adicionar o campo `click_id` na tabela `lead_clicks`.
2. **Backend**: Atualizar o `TrackingController` para salvar `click_id` e extrair UTMs caso não sejam enviados explicitamente.
3. **Frontend**: Sugerir script JS para a landing page que capture UTMs da URL e as envie para o Supabase.

### Como Validar
Simular um clique com UTMs:
```bash
curl -X POST http://localhost:3000/track/click \
  -H "Content-Type: application/json" \
  -d '{"hostname": "teste.com", "click_id": "123", "lp": "https://teste.com/?utm_source=meta&utm_campaign=blackfriday"}'
```
Verificar se o contato criado posteriormente recebe as atribuições `link_de_origem` e `campanha`.
