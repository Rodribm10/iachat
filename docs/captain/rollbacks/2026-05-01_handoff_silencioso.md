# Rollback — Handoff Silencioso (2026-05-01)

## Contexto

Mudança aplicada nos prompts da Dolce Amore (Valentina, assistant 6) e Prime AL (Bianca, assistant 2):

1. **Mensagem de handoff silenciosa.** Removidas todas as variações de "vou transferir", "vou chamar", "passar pra equipe". Substituídas por *"Um momento."* + chamada da tool de handoff.
2. **Postura "na dúvida, transfere".** Quando a agente NÃO tem a informação exata (ex: foto que o cliente pediu não está na galeria), em vez de improvisar/oferecer alternativa/continuar conversando, ela responde *"Um momento."* e faz handoff direto.

Decisão do Rodrigo: prefere errar transferindo demais (curva conservadora) a errar improvisando (resposta artificial). À medida que os prompts forem ficando mais robustos, a taxa de handoff cai naturalmente.

## Estado preservado ANTES da mudança

Arquivo `2026-05-01_prompts_snapshot.json` neste diretório contém o conteúdo completo (`config`, `response_guidelines`, `guardrails`, `orchestrator_prompt`, `description`, e todos os `scenarios` com `instruction` cru) puxado direto do banco de prod (stack `iachat`) ANTES de qualquer edição:

- **Assistant 2 (Bianca / Prime AL)** — 5 scenarios: Daniela_Reservas (id 4), Disponibilidade de suites (5), maria_fotos (6), Reclamacoes_Ouvidoria (13), outras_unidades (17).
- **Assistant 6 (Valentina / Dolce Amore)** — 5 scenarios: Daniela_Reservas (21), Disponibilidade de suites (22), maria_fotos (23), outras_unidades (24), Reclamacoes_Ouvidoria (25).

> Importante: o snapshot já reflete a edição feita HOJE no scenario 21 (Daniela_Reservas Dolce — REGRA #1 de NUNCA pedir valor pro cliente, +2142 chars). Esse fix de hoje deve ficar mesmo no rollback — não é parte do experimento de handoff.

## Como reverter

Em sessão futura, basta dizer "reverte o rollback de 2026-05-01 do handoff" — Claude vai abrir esse arquivo e rodar o procedimento abaixo.

### Procedimento de rollback

```ruby
# Roda dentro do container iachat_iachat_app via:
# ssh root@76.13.174.155 "docker exec <CID> bundle exec rails runner /tmp/rollback.rb"
require 'json'

data = JSON.parse(File.read('/tmp/2026-05-01_prompts_snapshot.json'))

data.each do |assistant_id, payload|
  a = Captain::Assistant.find(assistant_id.to_i)
  # Restaura colunas do assistant (NÃO toca em api_key, llm_model, etc — só o que tem prompt)
  a.update_columns(
    config: payload['config'],
    response_guidelines: payload['response_guidelines'],
    guardrails: payload['guardrails'],
    orchestrator_prompt: payload['orchestrator_prompt'],
    description: payload['description']
  )
  puts "Assistant #{a.id} (#{a.name}) restaurado."

  payload['scenarios'].each do |s_data|
    s = Captain::Scenario.find(s_data['id'])
    s.update_columns(
      title: s_data['title'],
      enabled: s_data['enabled'],
      instruction: s_data['instruction']
    )
    puts "  Scenario #{s.id} (#{s.title}) restaurado — #{s.instruction.size} chars."
  end
end
```

### Comandos exatos pra rodar o rollback

```bash
# 1. Copia o snapshot pra dentro do container
CID=$(ssh root@76.13.174.155 "docker ps --filter name=iachat_iachat_app -q | head -1")
scp docs/captain/rollbacks/2026-05-01_prompts_snapshot.json root@76.13.174.155:/tmp/
ssh root@76.13.174.155 "docker cp /tmp/2026-05-01_prompts_snapshot.json $CID:/tmp/"

# 2. Salva o script de rollback (ver bloco Ruby acima) em /tmp/rollback.rb localmente
# 3. Copia e roda
scp /tmp/rollback.rb root@76.13.174.155:/tmp/
ssh root@76.13.174.155 "docker cp /tmp/rollback.rb $CID:/tmp/ && docker exec $CID bundle exec rails runner /tmp/rollback.rb"
```

## Arquivos modelo afetados pela mudança

Pra também reverter os modelos no git (caso eu tenha commitado as mudanças):

**Dolce Amore:**
- `db/seed_prompts/_modelos/scenarios/jasmine_dolce_amore__daniela_reservas.md`
- `db/seed_prompts/_modelos/scenarios/jasmine_dolce_amore__maria_fotos.md`
- `db/seed_prompts/_modelos/scenarios/jasmine_dolce_amore__outras_unidades.md`
- `db/seed_prompts/_modelos/scenarios/jasmine_dolce_amore__reclamacoes_ouvidoria.md`
- `db/seed_prompts/_modelos/scenarios/jasmine_dolce_amore__disponibilidade_suites.md`
- `db/seed_prompts/_modelos/assistants/jasmine_dolce_amore.md`

**Prime AL:**
- (a localizar — o modelo do PrimeAL pode estar em `_modelos/scenarios/jasmine_primeal__*.md` ou similar)

## Critério de sucesso do experimento

- Reduzir % de respostas "criativas" da agente quando ela não tinha a info exata.
- Não deve haver explosão de handoff a ponto de saturar o time humano.
- Métrica: comparar volume de handoff/dia da Bianca (PrimeAL) na semana anterior vs. semana após mudança.

## Mudanças aplicadas em prod

Aplicado em 2026-05-01 via `update_columns` direto. Tamanhos antes → depois (chars):

| Item | DB id | Antes | Depois | Δ |
|---|---:|---:|---:|---:|
| Assistant Bianca / PrimeAL (orchestrator_prompt) | 2 | 6343 | 7078 | +735 |
| Assistant Valentina / Dolce (orchestrator_prompt) | 6 | 7476 | 8235 | +759 |
| Scenario PrimeAL daniela_reservas (instruction) | 4 | 21986 | 22481 | +495 |
| Scenario PrimeAL maria_fotos (instruction) | 6 | 3913 | 5124 | +1211 |
| Scenario Dolce daniela_reservas (instruction) | 21 | 24365 | 25117 | +752 |
| Scenario Dolce maria_fotos (instruction) | 23 | 4740 | 5799 | +1059 |

**Validação pós-sync:**
- Assistants: regra "NA DÚVIDA, TRANSFERE" + frase "Um momento." presentes em ambos.
- daniela_reservas: 2-3 ocorrências de "Um momento." em cada um.
- maria_fotos: 2-3 ocorrências de "Um momento." em cada um.

Cenários NÃO alterados (intencionalmente): `disponibilidade_suites`, `outras_unidades`, `reclamacoes_ouvidoria` — nenhum tinha frase robotizada de transferência problemática. `reclamacoes_ouvidoria` tem "Já tô chamando a recepção" / "Vou passar pro pedido pra gerência" mas isso é fala humana válida em hotelaria, não entrega que é robô — mantido.

## Critério de rollback (quando voltar atrás)

- Se o time humano reportar que está sendo soterrado de transferências.
- Se houver feedback de cliente "ela não me ajuda em nada, sempre transfere".
- Se os números mostrarem queda na conversão de reservas.
