require 'rails_helper'

RSpec.describe Captain::Codex::Translator do
  describe '.chat_to_responses' do
    it 'converts a simple chat completion to responses format' do
      chat = {
        'model' => 'gpt-5.4',
        'messages' => [
          { 'role' => 'system', 'content' => 'Você é um assistente.' },
          { 'role' => 'user', 'content' => 'Oi' }
        ]
      }

      result = described_class.chat_to_responses(chat)

      expect(result[:model]).to eq('gpt-5.4')
      expect(result[:stream]).to be true
      expect(result[:store]).to be false
      expect(result[:instructions]).to eq('Você é um assistente.')
      expect(result[:input]).to eq([{ role: 'user', content: 'Oi' }])
    end

    it 'joins multiple system messages into instructions' do
      chat = {
        'model' => 'gpt-5.4',
        'messages' => [
          { 'role' => 'system', 'content' => 'Parte 1' },
          { 'role' => 'system', 'content' => 'Parte 2' },
          { 'role' => 'user', 'content' => 'Oi' }
        ]
      }

      result = described_class.chat_to_responses(chat)

      expect(result[:instructions]).to eq("Parte 1\n\nParte 2")
    end

    it 'converts tools from chat format to responses format' do
      chat = {
        'model' => 'gpt-5.4',
        'messages' => [{ 'role' => 'user', 'content' => 'Oi' }],
        'tools' => [
          {
            'type' => 'function',
            'function' => {
              'name' => 'gerar_pix',
              'description' => 'Gera Pix',
              'parameters' => { 'type' => 'object', 'properties' => { 'valor' => { 'type' => 'number' } }, 'required' => ['valor'] }
            }
          }
        ]
      }

      result = described_class.chat_to_responses(chat)

      expect(result[:tools]).to eq([
                                     {
                                       type: 'function',
                                       name: 'gerar_pix',
                                       description: 'Gera Pix',
                                       parameters: { 'type' => 'object', 'properties' => { 'valor' => { 'type' => 'number' } },
                                                     'required' => ['valor'] },
                                       strict: false
                                     }
                                   ])
      expect(result[:tool_choice]).to eq('auto')
    end

    it 'translates tool_choice for specific function' do
      chat = {
        'model' => 'gpt-5.4',
        'messages' => [{ 'role' => 'user', 'content' => 'Oi' }],
        'tools' => [{ 'type' => 'function', 'function' => { 'name' => 'x' } }],
        'tool_choice' => { 'type' => 'function', 'function' => { 'name' => 'x' } }
      }

      result = described_class.chat_to_responses(chat)

      expect(result[:tool_choice]).to eq({ type: 'function', name: 'x' })
    end

    it 'translates assistant tool_calls history into function_call items' do
      chat = {
        'model' => 'gpt-5.4',
        'messages' => [
          { 'role' => 'user', 'content' => 'Gera Pix' },
          {
            'role' => 'assistant',
            'content' => nil,
            'tool_calls' => [
              { 'id' => 'call_abc', 'type' => 'function',
                'function' => { 'name' => 'gerar_pix', 'arguments' => '{"valor":100}' } }
            ]
          },
          { 'role' => 'tool', 'tool_call_id' => 'call_abc', 'content' => '{"ok":true}' },
          { 'role' => 'assistant', 'content' => 'Pronto!' }
        ]
      }

      result = described_class.chat_to_responses(chat)

      expect(result[:input]).to eq([
                                     { role: 'user', content: 'Gera Pix' },
                                     { type: 'function_call', call_id: 'call_abc', name: 'gerar_pix', arguments: '{"valor":100}' },
                                     { type: 'function_call_output', call_id: 'call_abc', output: '{"ok":true}' },
                                     { role: 'assistant', content: 'Pronto!' }
                                   ])
    end

    it 'maps max_tokens to max_output_tokens' do
      chat = {
        'model' => 'gpt-5.4',
        'messages' => [{ 'role' => 'user', 'content' => 'Oi' }],
        'max_tokens' => 500
      }

      expect(described_class.chat_to_responses(chat)[:max_output_tokens]).to eq(500)
    end

    it 'drops unsupported parameters like temperature' do
      chat = {
        'model' => 'gpt-5.4',
        'messages' => [{ 'role' => 'user', 'content' => 'Oi' }],
        'temperature' => 0.7,
        'top_p' => 0.9,
        'frequency_penalty' => 0.1
      }

      result = described_class.chat_to_responses(chat)

      expect(result.keys).not_to include(:temperature, :top_p, :frequency_penalty)
    end
  end

  describe '.responses_to_chat' do
    it 'converts a text-only response to chat completion format' do
      aggregated = {
        'id' => 'resp_abc',
        'model' => 'gpt-5.4',
        'output' => [
          {
            'type' => 'message',
            'content' => [{ 'type' => 'output_text', 'text' => 'Brasília.' }]
          }
        ],
        'usage' => { 'input_tokens' => 10, 'output_tokens' => 3, 'total_tokens' => 13 }
      }

      result = described_class.responses_to_chat(aggregated)

      expect(result[:id]).to eq('resp_abc')
      expect(result[:object]).to eq('chat.completion')
      expect(result[:model]).to eq('gpt-5.4')
      expect(result[:choices].first[:message]).to eq(role: 'assistant', content: 'Brasília.')
      expect(result[:choices].first[:finish_reason]).to eq('stop')
      expect(result[:usage]).to eq(prompt_tokens: 10, completion_tokens: 3, total_tokens: 13)
    end

    it 'converts a function_call response to tool_calls format' do
      aggregated = {
        'id' => 'resp_xyz',
        'model' => 'gpt-5.4',
        'output' => [
          {
            'type' => 'function_call',
            'call_id' => 'call_abc',
            'name' => 'gerar_pix',
            'arguments' => '{"valor":320}'
          }
        ],
        'usage' => { 'input_tokens' => 50, 'output_tokens' => 10, 'total_tokens' => 60 }
      }

      result = described_class.responses_to_chat(aggregated)

      message = result[:choices].first[:message]
      expect(message[:role]).to eq('assistant')
      expect(message[:content]).to be_nil
      expect(message[:tool_calls]).to eq([
                                           { id: 'call_abc', type: 'function', function: { name: 'gerar_pix', arguments: '{"valor":320}' } }
                                         ])
      expect(result[:choices].first[:finish_reason]).to eq('tool_calls')
    end

    it 'handles both text and tool_calls in the same response' do
      aggregated = {
        'id' => 'resp_mix',
        'model' => 'gpt-5.4',
        'output' => [
          { 'type' => 'message', 'content' => [{ 'type' => 'output_text', 'text' => 'Gerando...' }] },
          { 'type' => 'function_call', 'call_id' => 'c1', 'name' => 'x', 'arguments' => '{}' }
        ],
        'usage' => nil
      }

      result = described_class.responses_to_chat(aggregated)
      message = result[:choices].first[:message]

      expect(message[:content]).to eq('Gerando...')
      expect(message[:tool_calls].size).to eq(1)
      expect(result[:choices].first[:finish_reason]).to eq('tool_calls')
    end
  end
end
