namespace :captain do
  namespace :codex do
    desc 'Autentica o Captain AI com a assinatura ChatGPT Plus via device flow OAuth'
    task login: :environment do
      start = Captain::Codex::AuthService.start_device_login

      puts
      puts '=== Captain Codex OAuth Login ==='
      puts
      puts '1. Abra a URL abaixo no browser:'
      puts "   \e[36m#{start[:verify_url]}\e[0m"
      puts
      puts '2. Faça login com a conta ChatGPT Plus e cole o código:'
      puts "   \e[93m#{start[:user_code]}\e[0m"
      puts
      puts 'Aguardando autorização (timeout 15min, Ctrl+C para cancelar)...'

      deadline = 15.minutes.from_now
      result = nil

      loop do
        raise 'Timeout de 15min atingido' if Time.current > deadline

        sleep start[:poll_interval]
        begin
          result = Captain::Codex::AuthService.poll_once(
            device_auth_id: start[:device_auth_id],
            user_code: start[:user_code]
          )
          break
        rescue Captain::Codex::AuthService::PendingAuthorization
          print '.'
        end
      end

      puts
      puts 'Autorização recebida, trocando por tokens...'

      cred = Captain::Codex::AuthService.exchange_for_credential(
        authorization_code: result[:authorization_code],
        code_verifier: result[:code_verifier]
      )

      puts
      puts '✓ Login OK'
      puts "  Email: #{cred.email}"
      puts "  Plan: #{cred.chatgpt_plan_type}"
      puts "  ChatGPT account: #{cred.chatgpt_account_id}"
      puts "  Access token expira: #{cred.expires_at}"
      puts '  Refresh automático antes de cada call.'
    end

    desc 'Mostra status da credencial Codex ativa'
    task status: :environment do
      cred = Captain::CodexCredential.current
      if cred.nil?
        puts 'Nenhuma credencial Codex ativa. Rode: rails captain:codex:login'
        exit 1
      end

      puts "Status: #{cred.status}"
      puts "Email: #{cred.email}"
      puts "Plan: #{cred.chatgpt_plan_type}"
      puts "Expires at: #{cred.expires_at}"
      puts "Last refresh: #{cred.last_refresh_at}"
      puts "Needs refresh? #{cred.needs_refresh?}"
    end

    desc 'Força refresh da credencial Codex atual'
    task refresh: :environment do
      cred = Captain::CodexCredential.current
      if cred.nil?
        puts 'Nenhuma credencial ativa.'
        exit 1
      end

      refreshed = Captain::Codex::AuthService.refresh!(cred)
      puts "Refreshed. Nova expiração: #{refreshed.expires_at}"
    end
  end
end
