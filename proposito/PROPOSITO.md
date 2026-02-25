# Propósito do Produto — Fazer AI / Chatwoot Fork

> Documento vivo. Atualizado em: 2026-02-22

---

## 1. Propósito Central

Este repositório é um fork evolutivo do Chatwoot open-source para se tornar a plataforma de atendimento inteligente do ecossistema Fazer AI.

Nosso objetivo é entregar atendimento enterprise com IA nativa, WhatsApp e automações, sem depender de time técnico para ajustes operacionais do dia a dia.

---

## 2. Princípio Inegociável: Abertura Máxima ao Usuário Final

O produto deve sempre priorizar a maior abertura possível para o usuário final.

Em termos práticos:

- Sempre que for viável, a configuração deve existir no front-end/UI.
- Regras de negócio não devem ficar chumbadas no código quando puderem ser parametrizadas.
- Prompt, comportamento do agente, handoff, limites operacionais, integrações e fluxos devem ser gerenciáveis no painel.
- O backend deve atuar como camada de capacidade e segurança, não como gargalo de configuração.

Exceções permitidas:

- Segurança, compliance, integridade de dados e restrições de infraestrutura.
- Casos de performance crítica comprovada.

Regra de engenharia:

- Se houver dúvida entre hardcode e configuração em UI, escolher configuração em UI.
- Se um hardcode temporário for necessário, ele deve nascer com plano de migração para UI.

---

## 3. Visão de Produto

> "Toda empresa deve poder ter um atendimento de nível enterprise, com IA, WhatsApp e automações, sem precisar de um time de engenharia dedicado."

Público principal: empresas de médio porte (redes de pousadas, clínicas, academias, hotelaria e operações de serviço com alto volume em WhatsApp).

Problemas que resolvemos:

- Atendimento omnichannel com operação unificada (WhatsApp, email e web).
- IA capaz de responder, qualificar e executar tarefas reais (reserva, cobrança, consulta).
- Escalonamento fluido para humano quando necessário.
- Rastreabilidade total das ações de bot e humano.

---

## 4. Resultados Esperados do Produto

- Reduzir tempo médio de resposta e custo operacional por conversa.
- Aumentar taxa de resolução com IA sem perder controle humano.
- Dar autonomia operacional ao cliente final via painel de configuração.
- Evitar dependência de deploy para alterações de rotina.

---

## 5. Funcionalidades Implementadas (reference/chatwoot-develop)

As funcionalidades abaixo foram desenvolvidas no projeto de referência (`reference/chatwoot-develop`) e precisam ser portadas, adaptadas e melhoradas neste repositório:

### 5.1 🤖 Agentes de IA (Captain AI — v2)

| Feature | Descrição | Status |
|---------|-----------|--------|
| **Captain AI (Jasmine)** | Agente LLM principal que responde conversas automaticamente via WhatsApp | ✅ Implementado no reference |
| **Sistema de Tools** | Agente executando ferramentas: busca de FAQ, verificação de disponibilidade, consulta de preços, status de suítes | ✅ Implementado no reference |
| **Handoff para Humano** | IA detecta quando não sabe responder e transfere para agente humano, notificando via webhook | ✅ Implementado no reference |
| **Prompt Studio** | Interface para editar o prompt do agente em blocos modulares (system, persona, tools) diretamente no painel | ✅ Implementado no reference |
| **Análise de Imagem** | Agente recebe e processa imagens enviadas pelo cliente via WhatsApp | ✅ Implementado no reference |
| **Transcrição de Áudio** | Mensagens de áudio são transcritas e processadas pelo agente | ✅ Implementado no reference |
| **Sub-agentes** | Captain pode invocar agentes especializados (ex: agente de preços, agente de reservas) | ✅ Implementado no reference |
| **FAQ Lookup Tool** | Tool que busca respostas em base de conhecimento via embeddings | ✅ Implementado no reference |
| **Response Delay** | Simula tempo de digitação para tornar o bot mais humano | ✅ Implementado no reference |

### 5.2 📱 WhatsApp / Wuzapi Integration

| Feature | Descrição | Status |
|---------|-----------|--------|
| **Canal Wuzapi** | Integração com Wuzapi (WhatsApp não-oficial para dev/teste) | ✅ Parcialmente portado |
| **Webhook Wuzapi** | Recebimento de mensagens via webhook do Wuzapi | 🔧 Em ajuste |
| **Envio de Mensagens** | Envio de texto, imagem, arquivo e reações via Wuzapi | ✅ Implementado no reference |
| **Sync de mensagens enviadas pelo celular** | Mensagens enviadas pelo app do celular aparecem como "Enviadas" no Chatwoot | ✅ Implementado no reference |
| **QR Code flow** | Tela de escanear QR code ao criar o canal | ✅ Implementado |
| **Provisioning automático de usuário** | Ao criar o canal, cria automaticamente um usuário no Wuzapi | ✅ Implementado |

### 5.3 💳 Pagamentos PIX

| Feature | Descrição | Status |
|---------|-----------|--------|
| **PIX Stateful** | Fluxo completo de pagamento PIX dentro do chat (geração, polling, confirmação) | ✅ Implementado no reference |
| **PIX One-tap** | Pagamento PIX com um clique após dados já cadastrados | ✅ Implementado no reference |
| **PIX Público** | Geração de link de cobrança público sem autenticação | ✅ Implementado no reference |

### 5.4 📅 Reservas

| Feature | Descrição | Status |
|---------|-----------|--------|
| **Reserva via Chat** | Agente de IA cria reservas diretamente na conversa perguntando dados ao cliente | ✅ Implementado no reference |
| **Checagem de disponibilidade** | Tool que verifica disponibilidade de suítes em datas específicas | ✅ Implementado no reference |
| **Reserva PIX integrada** | Após confirmar reserva, gera cobrança PIX na mesma conversa | ✅ Implementado no reference |
| **Filtro por duração** | Filtro de reservas por período de estadia | ✅ Implementado no reference |

### 5.5 📊 Campanhas WhatsApp

| Feature | Descrição | Status |
|---------|-----------|--------|
| **Campanhas em massa** | Disparo de mensagens em lote via WhatsApp | ✅ Implementado no reference |
| **Rastreamento de cliques** | Captura UTM, referer, IP e geolocalização de links em campanhas | ✅ Implementado no reference |
| **Métricas de campanha** | Dashboard de cliques, conversões por campanha | ✅ Implementado no reference |

### 5.6 🏢 Multi-Unidade (Marcas / Brands)

| Feature | Descrição | Status |
|---------|-----------|--------|
| **Configuração por Unidade** | Cada inbox/unidade tem seu próprio webhook, prompt, agente e configurações | ✅ Implementado no reference |
| **Filtro de conversas por Unidade** | Agente/atendente vê apenas as conversas da sua unidade | ✅ Implementado no reference |

### 5.7 💬 UX / Interface

| Feature | Descrição | Status |
|---------|-----------|--------|
| **Atalhos de resposta** | Shortcuts customizados de resposta rápida | ✅ Implementado no reference |
| **Tradução de UI** | Traduções pt-BR para todas as interfaces novas | ✅ Implementado no reference |
| **Filtros avançados de conversas** | Filtrar por status, unidade, agente, data | ✅ Implementado no reference |

---

## 6. Funcionalidades Prioritárias Para Portar

> Lista priorizada do que ainda precisa ser implementado neste fork:

1. **`IncomingMessageWuzapiService` completo** — Recebimento de mensagens (texto, imagem, áudio, arquivo) corretamente roteado
2. **Handoff webhook** — Notificação externa quando IA transfere para humano
3. **Prompt Studio** — Interface de edição de prompts em blocos
4. **PIX Stateful** — Fluxo de pagamento dentro do chat
5. **Sub-agentes Captain** — Invoke de agentes especializados
6. **Campanhas WhatsApp com rastreamento** — Disparo + métricas
7. **Reservas** — Agente de reservas com disponibilidade e PIX

---

## 7. Arquitetura de IA

```
Cliente (WhatsApp)
       │
       ▼
  Wuzapi Server ──► Webhook ──► Chatwoot
                                    │
                          ┌─────────┴──────────┐
                          │  Captain AI Agent   │
                          │  (LLM + Tools)      │
                          └─────────┬──────────┘
                                    │
               ┌────────────────────┼────────────────────┐
               ▼                    ▼                    ▼
         FAQ Lookup           Reservas Tool         PIX Tool
         (Embeddings)         (Disponibilidade)     (Pagamento)
               │                    │                    │
               └────────────────────┴────────────────────┘
                                    │
                            Handoff se necessário
                                    │
                                    ▼
                            Agente Humano
```

---

## 8. Stack Tecnológica

| Camada | Tecnologia |
|--------|-----------|
| Backend | Ruby on Rails 7.1 |
| Frontend | Vue 3 + Vite |
| IA | OpenAI GPT-4.1 / Compatível OpenRouter |
| WhatsApp | Wuzapi (dev) / Evolution API (prod) |
| Banco de dados | PostgreSQL |
| Cache/Jobs | Redis + Sidekiq |
| Embeddings | pgvector (PostgreSQL) |

---

## 9. Diretrizes de Produto e Implementação

- Toda feature nova deve nascer com o mínimo de parâmetros essenciais expostos no painel.
- Configurações devem ser legíveis e editáveis por operação, não apenas por engenharia.
- Defaults podem existir, mas nunca bloquear customização quando ela fizer sentido de negócio.
- Evitar acoplamento entre comportamento do agente e constantes fixas em arquivo.
- Antes de fechar uma implementação, responder: "o usuário final consegue ajustar isso pela UI?"

---

## 10. Referências

- Projeto de referência com todas as features implementadas: `reference/chatwoot-develop/`
- Notas de progresso técnico: `reference/chatwoot-develop/progresso/`
- Plano de evolução Captain v2: `reference/chatwoot-develop/progresso/plano_evolucao_capitao_v2.md`
- Arquitetura dos bots: `reference/chatwoot-develop/progresso/arquitetura-bots.md`

---

*Documento mantido pelo time de arquitetura e produto do Fazer AI.*
