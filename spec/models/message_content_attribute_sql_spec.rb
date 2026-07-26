require 'rails_helper'

# `content_attributes` é coluna `json` com `store ..., coder: JSON`, o que grava o valor
# duplamente codificado (string JSON dentro do JSON). Consultas escritas como
# `content_attributes ->> 'chave'` nunca encontram nada — falham em silêncio, retornando
# zero linhas. Em produção isso deixou a detecção de loop, o filtro de reações e o dedup
# de emoji inoperantes por meses sem nenhum sinal de erro.
RSpec.describe Message, '.content_attribute_sql' do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }

  def criar_mensagem(attrs)
    create(:message, conversation: conversation, account: account, inbox: inbox, content_attributes: attrs)
  end

  it 'encontra a linha pela chave, apesar da dupla codificação' do
    alvo = criar_mensagem(external_source: 'hermes_callback')
    criar_mensagem(external_source: 'outra_coisa')

    encontrados = described_class.where("#{described_class.content_attribute_sql('external_source')} = ?", 'hermes_callback')

    expect(encontrados).to contain_exactly(alvo)
  end

  it 'prova que a forma ingênua não encontra nada (é por isso que o helper existe)' do
    criar_mensagem(external_source: 'hermes_callback')

    ingenua = described_class.where("content_attributes ->> 'external_source' = ?", 'hermes_callback')

    expect(ingenua).to be_empty
  end

  # É assim que o dedup de reação do Hermes funciona: as 10.847 reações em produção
  # guardam `in_reply_to` dentro de content_attributes (a coluna in_reply_to_id fica nula).
  it 'permite comparar valor numérico convertido' do
    original = criar_mensagem(external_source: 'mensagem_do_cliente')
    alvo = criar_mensagem(is_reaction: true, in_reply_to: original.id, external_source: 'hermes_auto_react')

    encontrados = described_class
                  .where("#{described_class.content_attribute_sql('external_source')} = ?", 'hermes_auto_react')
                  .where("(#{described_class.content_attribute_sql('in_reply_to')})::int = ?", original.id)

    expect(encontrados).to contain_exactly(alvo)
  end

  it 'devolve NULL quando a chave não existe, permitindo IS NULL' do
    sem_chave = criar_mensagem(external_source: 'algo')

    encontrados = described_class.where("#{described_class.content_attribute_sql('is_reaction')} IS NULL")

    expect(encontrados).to include(sem_chave)
  end

  it 'rejeita chave com caractere fora do padrão, para não abrir injeção de SQL' do
    expect { described_class.content_attribute_sql("x' OR 1=1 --") }.to raise_error(ArgumentError)
  end
end
