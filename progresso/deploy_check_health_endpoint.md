# Correção do Deploy Check da Review App

## Objetivo
Corrigir a falha no pipeline de CI "Deploy Check" (`.github/workflows/deploy_check.yml`) que quebrava após 10 tentativas devido à Review App (Heroku) não retornar o healthcheck esperado.

## Contexto
O workflow do GitHub Actions esperava um JSON do endpoint `/api` contendo os campos `version`, `timestamp`, `queue_services` e `data_services` todos populados e com valor `"ok"` pros serviços. Porém, o endpoint `/api` (referente ao `ApiController#index`) não era exposto corretamente em alguns ambientes ou levantava erro 500 caso o Redis/Postgres demorassem a subir, além de cair em um loop infinito no script bash porque a variável `$attempt` não era incrementada se a chamada HTTP retornasse 200 mas o JSON fosse inválido.

## Passos Realizados
1. Mapeamos que já existia uma rota `get '/health', to: 'health#show'` apontando para o `HealthController` que apenas respondia `{ status: 'woot' }`.
2. Alteramos o `HealthController#show` para retornar o JSON robusto exigido pelo workflow, fazendo o ping no Redis e no Postgres e blindando as exceções com `rescue StandardError` para nunca retornar 500 durante a fase de boot.
3. Editamos o arquivo `.github/workflows/deploy_check.yml`:
   - Trocamos o `curl` de `/api` para `/health`.
   - Adicionamos a instrução `attempt=$((attempt + 1))` no bloco `else` (quando o teste do `jq` não passa), corrigindo o loop infinito.
   - Aumentamos o `max_attempts` de 10 para 15 (dando 45 minutos de tolerância para a Review App subir o banco de dados e os dynos completamente).

## Principais Arquivos Alterados
- `app/controllers/health_controller.rb`
- `.github/workflows/deploy_check.yml`

## Como Validar
1. Subir essas alterações (commit e push) na branch do PR.
2. Acompanhar a aba "Actions" no GitHub e verificar o job "Check Deployment (pull_request)".
3. O script bash deverá fazer o cURL em `/health` e, assim que o PostgreSQL e Redis reportarem `"ok"`, o step será marcado como "Deployment successful".

## Como Reverter
Basta fazer um git revert do commit que adicionou essas alterações ou retornar os arquivos aos estados anteriores (o `HealthController` retornando apenas `{ status: 'woot' }` e o `deploy_check.yml` voltando para `/api` sem o incremento).
