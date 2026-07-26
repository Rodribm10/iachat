# Calibra o juiz de FAQ contra um gabarito rotulado à mão.
#
# É o único trabalho humano obrigatório do ciclo de aprendizado: uma vez, o dono
# rotula 20–30 candidatas reais como aprovada/reprovada. Se o juiz concordar em
# pelo menos 70% dos casos, ele pode substituir a aprovação manual. Abaixo
# disso, ajuste o prompt do juiz — nunca o gabarito.
#
# Formato do arquivo (JSON):
#   [
#     {
#       "question": "Vocês aceitam pet?",
#       "answer": "Não aceitamos animais em nenhuma unidade.",
#       "conversa": "cliente: vocês aceitam pet?\nagente: não aceitamos...",
#       "esperado": "aprovado"
#     }
#   ]
#
# Uso:
#   bundle exec rake 'captain:judge_calibration[/caminho/gabarito.json,11]'
namespace :captain do
  desc 'Exporta candidatas reais (FAQs pendentes vindas de conversa) para rotular à mão'
  task :judge_gabarito, %i[saida limite] => :environment do |_task, args|
    saida = args[:saida].presence || 'gabarito.json'
    limite = (args[:limite].presence || 30).to_i

    candidatas = Captain::AssistantResponse
                 .pending
                 .where(documentable_type: 'Conversation')
                 .order(created_at: :desc)
                 .limit(limite)

    linhas = candidatas.map do |faq|
      {
        'id' => faq.id,
        'assistant' => faq.assistant&.name,
        'question' => faq.question,
        'answer' => faq.answer,
        'conversa' => faq.documentable.try(:to_llm_text).to_s.truncate(4000),
        'esperado' => '' # PREENCHER: "aprovado" ou "reprovado"
      }
    end

    File.write(saida, JSON.pretty_generate(linhas))

    puts "#{linhas.size} candidatas exportadas para #{saida}"
    puts 'Preencha o campo "esperado" de cada uma com "aprovado" ou "reprovado" e rode:'
    puts "  bundle exec rake 'captain:judge_calibration[#{saida},<assistant_id>]'"
    puts "\nATENÇÃO: o arquivo contém conversas reais de clientes. Não commite no git."
  end

  desc 'Calibra o juiz de FAQ contra um gabarito rotulado (arquivo JSON, assistant_id)'
  task :judge_calibration, %i[file assistant_id] => :environment do |_task, args|
    abort('Informe o arquivo do gabarito: rake captain:judge_calibration[arquivo.json,assistant_id]') if args[:file].blank?

    entries = JSON.parse(File.read(args[:file], encoding: 'UTF-8'))
    assistant = Captain::Assistant.find(args[:assistant_id])
    fake_conversation = Struct.new(:to_llm_text)

    # Permite calibrar contra um endpoint OpenAI-compatível diferente do provider
    # configurado (ex.: proxy local do Hermes) sem alterar InstallationConfig.
    if ENV['JUDGE_API_BASE'].present?
      RubyLLM.configure do |config|
        config.openai_api_key = ENV.fetch('JUDGE_API_KEY', 'local-proxy')
        config.openai_api_base = ENV.fetch('JUDGE_API_BASE')
        config.request_timeout = ENV.fetch('JUDGE_TIMEOUT', '300').to_i
      end
      puts "Endpoint sobrescrito: #{ENV.fetch('JUDGE_API_BASE')}"
    end

    modelo = ENV['JUDGE_MODEL'].presence
    Captain::Llm::FaqJudgeService.define_singleton_method(:judge_model) { modelo } if modelo

    concorrencia = ENV.fetch('CONCURRENCY', '1').to_i.clamp(1, 8)
    puts "Casos: #{entries.size} | juiz: #{Captain::Llm::FaqJudgeService.judge_model} | paralelismo: #{concorrencia}"

    # Um caso de contradição só é avaliável se o juiz receber o conhecimento que
    # ele contradiz. Sem isso o juiz aprova por omissão ("não há conhecimento
    # relacionado na base") e a calibração mede menos do que parece medir.
    vizinho_struct = Struct.new(:question, :answer)
    montar_vizinhos = lambda do |entry|
      Array(entry['vizinhos']).map { |v| vizinho_struct.new(v['question'], v['answer']) }
    end

    fila = Queue.new
    entries.each_with_index { |entry, index| fila << [entry, index] }
    veredictos = Array.new(entries.size)

    Array.new(concorrencia) do
      Thread.new do
        while (item = begin
          fila.pop(true)
        rescue ThreadError
          nil
        end)
          entry, index = item
          veredictos[index] = Captain::Llm::FaqJudgeService.new(
            assistant: assistant,
            question: entry['question'],
            answer: entry['answer'],
            conversation: fake_conversation.new(entry['conversa'].to_s),
            neighbours: montar_vizinhos.call(entry)
          ).call
          print '.'
          $stdout.flush
        end
      end
    end.each(&:join)

    agreements = 0
    disagreements = []
    erros = veredictos.count { |v| v[:raw]['erro'].present? }

    # Juiz sem LLM reprova tudo. Sem esta trava, a saída seria uma
    # concordância aparentemente plausível (~50%) em cima de zero avaliação.
    if erros == entries.size
      abort("\n\nERRO: o juiz não conseguiu falar com o LLM em nenhum caso. Nenhuma avaliação foi feita.\n" \
            "Motivo: #{veredictos.first[:raw]['erro'].to_s.squish.truncate(240)}\n\n" \
            "Verifique a credencial do provider (#{Captain::Llm::ProviderConfig.provider}) ou use " \
            'JUDGE_API_BASE para apontar a um endpoint alternativo.')
    end

    entries.each_with_index do |entry, index|
      actual = veredictos[index][:approved] ? 'aprovado' : 'reprovado'
      expected = entry['esperado'].to_s

      if actual == expected
        agreements += 1
      else
        disagreements << { index: entry['caso'] || (index + 1), question: entry['question'], expected: expected,
                           actual: actual, motivo: veredictos[index][:raw] }
      end
    end

    puts "\n\n== Calibração do juiz =="
    puts "Casos: #{entries.size}"

    if erros.positive?
      puts "\nATENÇÃO: #{erros} de #{entries.size} chamadas falharam no LLM."
      puts 'O percentual abaixo NÃO vale — chamada que falha vira reprovação automática.'
    end

    puts "Concordância: #{agreements}/#{entries.size} (#{(agreements * 100.0 / entries.size).round(1)}%)"

    if disagreements.any?
      puts "\nDivergências (ajuste o PROMPT do juiz, não o gabarito):"
      disagreements.each do |d|
        puts "\n##{d[:index]} #{d[:question]}"
        puts "  esperado: #{d[:expected]} | juiz: #{d[:actual]}"
        puts "  motivos: #{d[:motivo].except('model', 'judged_at')}"
      end
    end

    puts "\nMínimo para ligar em produção: 70%."
  end
end
