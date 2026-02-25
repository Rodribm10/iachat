# Ajuste de Orquestração + Guardrail de FAQ (Captain/Jasmine)

**Data:** 24/02/2026  
**Autor:** Codex (AI Developer)

## Objetivo
Garantir que o agente **não responda “não sei / não tenho acesso” sem antes consultar FAQ**, e evitar que a conversa fique presa em um cenário que ignora FAQ.

## Problema Observado
- Em algumas conversas, o agente respondia corretamente usando FAQ (ex.: preços), mas em outras respostas dizia que “não tinha acesso” (ex.: senha do Wi-Fi).
- Isso gerava comportamento inconsistente e perda de confiança.

## Causa-Raiz
1. **Sticky de cenário no histórico**  
   O runner podia iniciar o turno no último `agent_name` do histórico (ex.: cenário de disponibilidade), em vez de iniciar no orquestrador principal.

2. **Guardrail com detecção ampla demais de `faq_lookup`**  
   A checagem considerava `faq_lookup` em `result.messages` inteiro.  
   Se houve `faq_lookup` em turno anterior, isso podia bloquear o fallback no turno atual.

## O que foi implementado

### 1) Início de turno sempre pelo orquestrador
- O contexto da execução foi padronizado para iniciar no agente principal (`current_agent` do assistente).
- O `conversation_history` enviado ao runner zera `agent_name` das mensagens para evitar lock indevido em cenário.

### 2) Guardrail de FAQ para respostas de incerteza
- Foi criado um guardrail em `AgentRunnerService`:
  - Detecta respostas de incerteza (`não sei`, `não tenho`, etc.).
  - Se **não houve `faq_lookup` no turno atual**, dispara fallback de FAQ via busca semântica (`@assistant.responses.approved.search(query)`).
  - Se encontrar resposta no FAQ, substitui a resposta final.
  - Se não encontrar, responde explicitamente:
    - “Consultei o FAQ e não encontrei essa informação cadastrada ainda...”
    - Evita resposta genérica “não sei” sem contexto.

### 3) Correção de escopo do `faq_lookup`
- A verificação agora considera apenas mensagens **após a última pergunta do usuário do turno atual**.
- Isso evita falso positivo de `faq_lookup` antigo.

## Arquivos Alterados
- `/Users/user/Dev/Produtos/Chatwoot-fazer-ai/fazer-ai-kanban/chatwoot/enterprise/app/services/captain/assistant/agent_runner_service.rb`
- `/Users/user/Dev/Produtos/Chatwoot-fazer-ai/fazer-ai-kanban/chatwoot/spec/enterprise/services/captain/assistant/agent_runner_service_spec.rb`

## Testes e Validação
- Executado:
  - `bundle exec rspec spec/enterprise/services/captain/assistant/agent_runner_service_spec.rb`
- Resultado:
  - **29 examples, 0 failures**

Casos cobertos em teste:
- fallback aplicado quando resposta incerta vem sem `faq_lookup`;
- não aplica fallback quando `faq_lookup` ocorreu no turno atual;
- aplica fallback quando `faq_lookup` ocorreu apenas em turno anterior;
- retorna mensagem explícita de “FAQ não encontrado” quando busca não acha nada.

## Observabilidade (logs)
Foram mantidos logs para rastrear guardrail:
- Trigger do guardrail com query;
- Quantidade de resultados encontrados na busca FAQ;
- Falha de fallback (se houver exception).

## Impacto Prático
- O agente deixa de “desistir” sem consultar conhecimento.
- Reduz respostas incoerentes entre perguntas parecidas.
- Mantém handoff para humano apenas quando realmente necessário.

## Limitações Atuais
- Se o FAQ estiver mal cadastrado ou com baixa qualidade semântica, o fallback ainda pode não encontrar resposta.
- O guardrail atua em respostas de incerteza; não corrige respostas erradas factualmente quando o modelo responde com confiança indevida.

## Próximos Passos Recomendados
1. Revisar/normalizar entradas de FAQ críticas (Wi-Fi, horários, políticas, preços).
2. Adicionar métrica de “fallback guardrail acionado” por inbox/assistente.
3. Opcional: forçar política “FAQ-first” para intents informativas antes de responder livremente.
