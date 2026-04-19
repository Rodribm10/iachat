# Habilitando a Memória Semântica do Captain (Contact Memory)

Este guia explica como ligar/desligar, por conta (Account), as duas feature flags
que controlam o subsistema de memória semântica de contatos do Captain:

- `captain_contact_memory_extraction_enabled` — habilita a extração assíncrona de
  fatos duráveis a partir das conversas do contato (job
  `Captain::ContactMemories::ExtractFromConversationJob` e derivados).
- `captain_contact_memory_recall_enabled` — habilita a recuperação das memórias
  mais relevantes na construção do prompt do assistente
  (`Captain::Assistant::MemoryPromptInjector`).

Ambas são armazenadas em `Account#custom_attributes` (JSONB) e lidas via os
helpers definidos em `app/models/concerns/captain_featurable.rb`:

```ruby
account.captain_contact_memory_extraction_enabled? # => true/false
account.captain_contact_memory_recall_enabled?     # => true/false
```

Por padrão, ambas retornam `false` quando a chave não está presente.

> **Observação:** estas flags vivem em `custom_attributes` — não confundir com o
> hash `captain_features` (usado pelos toggles da tela de Captain Settings para
> Editor/Assistant/Copilot/Label Suggestion/Help Center Search/Audio
> Transcription). O toggle de UI para Contact Memory está deferido; use este
> procedimento via console até que a UI seja implementada em uma iteração
> futura.

## Procedimento — Rails console

### 1. Abrir o console

Em produção/staging (container `rails`):

```bash
docker compose exec rails bin/rails console
```

Localmente:

```bash
bin/rails console
```

### 2. Habilitar as flags para uma conta específica

Substitua `ACCOUNT_ID` pelo ID da conta desejada.

```ruby
account = Account.find(ACCOUNT_ID)

account.update!(
  custom_attributes: account.custom_attributes.merge(
    'captain_contact_memory_extraction_enabled' => true,
    'captain_contact_memory_recall_enabled' => true
  )
)

# Verificação
account.captain_contact_memory_extraction_enabled? # => true
account.captain_contact_memory_recall_enabled?     # => true
```

### 3. Desabilitar as flags

```ruby
account = Account.find(ACCOUNT_ID)

account.update!(
  custom_attributes: account.custom_attributes.merge(
    'captain_contact_memory_extraction_enabled' => false,
    'captain_contact_memory_recall_enabled' => false
  )
)
```

Se preferir remover as chaves ao invés de setar `false` (comportamento idêntico,
pois o default é `false`):

```ruby
account = Account.find(ACCOUNT_ID)
account.custom_attributes.delete('captain_contact_memory_extraction_enabled')
account.custom_attributes.delete('captain_contact_memory_recall_enabled')
account.save!
```

### 4. Habilitar em lote (rollout)

Para habilitar em várias contas de uma vez:

```ruby
Account.where(id: [1, 2, 3]).find_each do |account|
  account.update!(
    custom_attributes: account.custom_attributes.merge(
      'captain_contact_memory_extraction_enabled' => true,
      'captain_contact_memory_recall_enabled' => true
    )
  )
end
```

## Estratégia de rollout recomendada

As duas flags são independentes e podem ser habilitadas em fases:

1. **Fase de coleta (somente extração):** ligue apenas
   `captain_contact_memory_extraction_enabled`. Os jobs começam a popular a
   tabela `captain_contact_memories` sem afetar o prompt do assistente.
2. **Fase de uso (coleta + recall):** após acumular dados suficientes (sugestão:
   7–14 dias), ligue também `captain_contact_memory_recall_enabled`. O
   `MemoryPromptInjector` passa a inserir as memórias relevantes no contexto do
   LLM.
3. **Rollback:** desligar `captain_contact_memory_recall_enabled` sai do prompt
   imediatamente (sem exigir limpeza de dados). Desligar a extração interrompe
   novas coletas mas mantém o histórico.

## Verificação pós-ativação

Depois de habilitar, confirme via console:

```ruby
# Memórias extraídas para a conta
Captain::ContactMemory.where(account_id: ACCOUNT_ID).count

# Últimas memórias criadas
Captain::ContactMemory.where(account_id: ACCOUNT_ID)
                      .order(created_at: :desc)
                      .limit(5)
                      .pluck(:id, :contact_id, :content, :created_at)
```

Logs relevantes no Sidekiq: jobs da namespace
`Captain::ContactMemories::*` (extração, envelhecimento, checagem de
contradição, detecção de silêncio, atualização de embedding, hard delete).

## Próximos passos — UI de toggles (deferido)

Um painel "Memória do Cliente" na página de Captain Settings, com dois
`Switch`es ligados a estas flags, é a evolução natural. Não foi implementado
nesta task porque:

- O componente `FeatureToggle` existente está acoplado ao store
  `captainConfigStore` e ao hash `captain_features`/`captain_models` — não
  cobre flags em `custom_attributes`.
- Um toggle de `custom_attributes` exige um novo componente + chamada ao
  endpoint de `PATCH /api/v1/accounts/:id` (já existente) e, potencialmente, um
  novo store action para refletir o estado localmente.

A implementação deve:

1. Criar um `CustomAttributeToggle.vue` em
   `app/javascript/dashboard/routes/dashboard/settings/captain/components/`.
2. Usar o `AccountAPI` (`app/javascript/dashboard/api/account.js`) para
   persistir via `PATCH /api/v1/accounts/:id` com
   `{ custom_attributes: { ... } }`.
3. Adicionar uma nova `SectionLayout` em `Index.vue` com título
   "Memória do Cliente" e dois toggles.
4. Adicionar chaves i18n em
   `app/javascript/dashboard/i18n/locale/{en,pt_BR}/captain.json`.
