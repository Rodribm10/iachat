# Correção do Envio de Fotos (send_suite_images_tool)

**Objetivo:** Garantir que a IA envie fotos condizentes com o pedido do cliente (por Categoria ou Número da Suíte), resolvendo o bug onde a IA enviava fotos de categorias erradas e misturadas por causa de inferência baseada em regex.

**Arquivos Alterados:**
- `enterprise/app/services/captain/tools/send_suite_images_tool.rb`

**Implementação:**
1. Foi removido o bloco que tentava inferir (`infer_suite_number_from_last_incoming_message`) o parâmetro `suite_number` a partir da última mensagem usando um Regex falho (que confundia nomes de categorias, ex: "alexa", julgando-as como `suite_number`).
2. Adicionada validação estrita no início do método `execute`:
   - A ferramenta foi forçada a exigir ou `suite_category` ou `suite_number`.
   - Se os dois estiverem em branco, agora retorna `error_response` guiando a IA: *"Erro: Para buscar fotos, é obrigatório informar o parâmetro suite_category ou suite_number correspondente ao pedido do cliente."*
3. Com o erro explícito devolvido à LLM e sem a inferência mágica de background, o agente será forçado a preencher os parâmetros corretos para que a query do ActiveRecord filtre perfeitamente a categoria.

**Como Validar:**
Basta pedir: "Me manda foto da suíte alexa". A IA vai chamar a ferramenta passando `suite_category: "alexa"` e receberá apenas as fotos da categoria Alexa.
