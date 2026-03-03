#!/bin/bash
# Script de teste rápido da Landing Page simulando tráfego

# Defina a URL base local, se o porto for 3000
BASE_URL="http://localhost:3000/lp"

# Imprime o título de teste e a URL para clicar
echo "---------------------------------------------------------"
echo "Teste a sua Landing Page abrindo este link no navegador:"
echo ""
echo "  👉  $BASE_URL"
echo ""
echo "Teste também com UTMs simulando um clique de Anúncio:"
echo ""
echo "  👉  $BASE_URL?utm_source=meta&utm_medium=cpc&utm_campaign=black_friday"
echo ""
echo "Abra os links acima. Eles buscarão as configurações salvas"
echo "pelo seu painel do Chatwoot (se houver configuração"
echo "para 'localhost', ela aparecerá)."
echo "---------------------------------------------------------"
