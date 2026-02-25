# Plano de Ação: Arquitetura de IA para o Novo Chatwoot

## 1. O Problema Anterior
No projeto legado (referência: `reference/chatwoot-develop`), os módulos de IA (Jasmine, Captain, CrmInsights) foram injetados em listeners globais e workers que processavam *todas* as mensagens ou rodavam rotinas frequentes. Isso levou a um uso indiscriminado e excessivo de tokens LLM (OpenAI), resultando em custos insustentáveis.

## 2. A Nova Abordagem: Sob Demanda e Controlado
Neste novo projeto, a arquitetura será desenhada para que a IA seja ativada apenas quando estritamente necessário ou configurado, evitando vazamentos e processamento redundante.

### 2.1 Integrações WhatsApp (Canais)
As integrações Wuzapi e Evolution API serão importadas do projeto antigo para garantirmos a funcionalidade de base.
**Ação:** Trazer endpoints, services (providers) e UI de configurações limitados a estas duas integrações de canal. Prioritizar manutenibilidade para facilitar atualizações futuras do Chatwoot core.

### 2.2 Bot de Atendimento e FAQ
**Ação:**
- **Utilizar Padrão Nativo (`AgentBot`):** Ao invés de um listener global (`jasmine_listener`), criaremos a IA como um `AgentBot` do Chatwoot.
- O processamento de RAG (Busca Semântica no Knowledge Base) ocorrerá de forma orgânica e **somente nas conversas atribuídas ao AgentBot (status: pending/bot-assigned)**.
- O contexto a ser enviado ao LLM será resumido e utilizaremos Cache ou restrição de contexto para as últimas X mensagens para baratear o "Cached Input".

### 2.3 Bot de Reservas e Fluxos Complexos (Especialista/Function Calling)
**Ação:**
- Em vez de ter um "Captain" rodando sobre toda mensagem, adotaremos **Roteamento Híbrido**:
  1. Identificação simples (com modelo barato ou rules-engine/nlu light) se a intenção é "reserva" ou consultar "preço/disponibilidade".
  2. Uso de function calling estrito apenas quando dentro desse funil específico, minimizando tokens.
- O histórico não crescerá infinitamente no payload. Quando coletado dado do cliente (ex: quarto, data), será guardado em KV ou banco de dados (contexto da reserva) em vez de precisar que o LLM releia todo o histórico gigante.

### 2.4 Análise / Resumo de CRM (CrmInsights)
**Ação:**
- **Remoção de Background Jobs Frequentes:** Não rodar script periódico monitorando conversas para resumos ou sentimento.
- **Hooks sob Demanda:** A análise visual e a extração estruturada ocorrerá:
  a) Diretamente num botão manual acionado pelo humano.
  b) No exato momento de **RESOLVER** (Resolved) a conversa, onde estruturamos o JSON do ticket e salvamos no banco, servindo como relatório pós-venda (uma execução por ticket).

## 3. Próximos Passos Iniciais
- **Bloqueio do Legado:** Aplicamos um "return" antecipado (`early return`) no projeto legado (`reference/chatwoot-develop`) nos três pontos mapeados: `jasmine_listener.rb`, `processor_service.rb` e `update_job.rb`. Isso foi feito para garantir a paralisação do vazamento financeiro lá, mantendo o sistema em pé, apenas com atendimento humano.
- **Implementação Nova:** Agora que o custo do outro projeto está congelado, podemos iniciar a implantação das funcionalidades neste novo projeto de forma controlada através da funcionalidade nativa de AgentBots.
