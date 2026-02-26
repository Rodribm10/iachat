# Adicionando Data e Hora Atual no Contexto da IA

**Objetivo:** Permitir que tanto o Assistente Principal quanto os Cenários da IA tenham ciência da data, hora e fuso horário atuais (Brasília) para melhor precisão em tarefas e respostas rotineiras (ex: "Que dia é hoje?", agendamentos, etc).

**Arquivos Alterados:**
- `enterprise/app/models/captain/assistant.rb` (Método `prompt_context`)
- `enterprise/app/models/captain/scenario.rb` (Método `prompt_context`)
- `enterprise/lib/captain/prompts/assistant.liquid` (Template principal da IA)
- `enterprise/lib/captain/prompts/scenario.liquid` (Template dos cenários da IA)

**Implementação:**
1. Injetadas no backend as variáveis:
   - `current_date: Time.current.in_time_zone('Brasilia').strftime('%d/%m/%Y')`
   - `current_time: Time.current.in_time_zone('Brasilia').strftime('%H:%M')`
   - `current_timezone: 'Horário de Brasília (BRT/BRST)'`
2. Modificados os arquivos de template Liquid para exibir este contexto logo acima de `# Current Context`.

**Risco/Trade-offs Controlados:**
Ocupa cerca de ~15 tokens fixos no system prompt com os dados temporais. É um custo mínimo garantindo excelente retorno para a percepção humana da inteligência e capacidade situacional da IA.

**Como Validar:**
Basta conversar com a IA e questionar "Que horas são agora?" ou "Qual a data de hoje?".
