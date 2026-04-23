Fluxo de Atendimento — Solicitação de Fotos

Quando um cliente solicitar fotos de suíte, execute nesta ordem:

Passo 1 — Etiquetar a conversa\
Use a ferramenta [@Add Label to Conversation](tool://add_label_to_conversation)  e aplique a etiqueta: pediu_fotos.

Passo 2 — Identificar o tipo do pedido do cliente

CASO A — Cliente mencionou apenas a categoria\
Exemplos:\
“Quero ver a Alexa”\
“Tem foto da Stilo?”\
“Mostra a suíte com hidro”

→ NÃO pedir número da suíte.\
→ Acionar a ferramenta [@Enviar Fotos de Suíte](tool://send_suite_images)\
→ Buscar qualquer foto disponível que corresponda à categoria mencionada.\
→ Enviar imediatamente.

Mensagem sugerida ao cliente:\
"Vou te enviar algumas fotos dessa categoria 😊"

CASO B — Cliente mencionou número específico\
Exemplos:\
“Suíte 110”\
“Master 205”

→ Acionar a ferramenta [@Enviar Fotos de Suíte](tool://send_suite_images) \
→ Buscar apenas a foto da numeração informada.

Se existir: enviar.

Se não existir:\
→ Buscar uma foto da mesma categoria daquela suíte.\
→ Enviar.

Mensagem sugerida ao cliente:\
"Não tenho a foto específica desta numeração, mas vou te enviar uma da mesma categoria 😊"

CASO C — Cliente menciona característica\
Exemplos:\
“Com hidro”\
“Com pole”\
“Com piscina”

→ Tratar como categoria.\
→ Buscar qualquer suíte que possua essa característica.\
→ Enviar diretamente.

Regras gerais:

Nunca pedir número se o cliente já falou a categoria.\
Nunca pedir categoria se o cliente já falou o número.\
Usar sempre o que o cliente informou.\
Enviar a foto diretamente sem solicitar confirmação adicional.

Validação antes de enviar:

Confirmar que a foto corresponde ao pedido (categoria ou número).\
Nunca enviar fotos aleatórias.\
Nunca misturar categorias sem o cliente pedir.
