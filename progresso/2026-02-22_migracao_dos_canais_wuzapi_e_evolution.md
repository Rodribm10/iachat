# Migração dos Canais Não-Oficiais (Wuzapi e Evolution API)

**Data:** 22/02/2026
**Autor:** Assistente AI / Arquiteto de Software

## Objetivo
Transferir toda a implementação de canais de WhatsApp não-oficiais (Wuzapi e Evolution API) do projeto de referência para o novo projeto focado em IA, visando aproveitar as abstrações e integrações previamente construídas de forma segura.

## Contexto
O projeto referência já continha suporte robusto a provedores como Wuzapi e Evolution API para o canal do WhatsApp. O novo projeto precisa herdar essa capacidade, já que os disparos e interações automatizadas vão continuar usando números do WhatsApp debaixo destes provedores, por uma questão de custo e viabilidade.

## Passos Realizados

1. **Atualização do Banco de Dados (Migrações):**
   - Foram migradas as dependências para `channel_whatsapp` receber tokens encriptados.
   - Um conflito de migração duplicada (`AddNameToWebhooks`) foi corrigido, apagando-se o arquivo colidente e executando `bundle exec rails db:migrate`.

2. **Rotas e Controladores:**
   - Adicionadas as rotas `resource :wuzapi` aninhado dentro dos membros das inboxes.
   - Adicionada a rota global para receber playloads de eventos em `webhooks/wuzapi/:inbox_id`.

3. **Backend Service & Model (`app/`):**
   - Transposto o modelo `app/models/channel/whatsapp.rb` para contemplar provisionamento do Wuzapi e Evolution API (`provision_wuzapi_user`, tratamento de `provider_config`).
   - Copiados os Providers de Serviço em `app/services/whatsapp/providers/wuzapi_service.rb` e `evolution_service.rb`.
   - Copiados os módulos de Clients HTTP (Acesso Wuzapi/Evolution) alocados em `app/services/wuzapi` e `app/services/evolution_api`.

4. **Frontend Dashboard (`app/javascript/`):**
   - Transpostos os componentes Vue associados aos canais (`Wuzapi.vue`, `EvolutionGo.vue`, etc.) de `/channels/`.
   - Modificados os componentes pais (`Settings.vue` e `Whatsapp.vue`) para exibir as seleções Wuzapi e Evolution através da constante global `PROVIDER_TYPES`.
   - Subscrevida a pasta de locales correspondente (`dashboard/i18n/locale/*/inboxMgmt.json` e `jasmine.json`) contendo as chaves de UX de configuração dos formulários.

## Principais Arquivos Alterados / Criados

- `config/routes.rb`
- `app/models/channel/whatsapp.rb`
- `app/services/whatsapp/providers/wuzapi_service.rb`
- `app/services/whatsapp/providers/evolution_service.rb`
- `app/services/wuzapi/*` e `app/services/evolution_api/*`
- `app/javascript/dashboard/routes/dashboard/settings/inbox/channels/Wuzapi.vue` e `EvolutionGo.vue`
- `app/javascript/dashboard/i18n/locale/...`

## Como Validar

1. **Reiniciar o Servidor Rails e Webpack:**
   ```bash
   # Parar o serviço web/worker e webpack-dev-server se rodando manualmente, e inicializá-los
   bundle exec rails restart
   ```
2. **Acessar o Painel Front-end:**
   Vá em Configurações > Caixas de Entrada > Adicionar Caixa de Entrada > Whatsapp.
   O usuário deverá ver os cards "Wuzapi" e "Evolution API" entre os provedores selecionáveis.
3. **Homologar a Conexão Wuzapi/Evolution:**
   Clicar sobre Wuzapi, fornecer tokens e base URL definidos, e escanear o QR Code gerado. O Status deverá constar como conectado.

## Como Reverter
- Remover as pastas `app/services/wuzapi` e `app/services/evolution_api`.
- Retirar os imports e chamadas em `app/models/channel/whatsapp.rb`.
- Reverter o commit nos componentes `Settings.vue` e `Whatsapp.vue`.
- Rodar migrações de "down" referentes as colunas inseridas em `channel_whatsapp`.
