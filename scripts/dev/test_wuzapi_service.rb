require_relative 'config/environment'
payload = {
  "event" => {
    "Info" => {
      "Type" => "text",
      "Sender" => "556182098580@s.whatsapp.net",
      "PushName" => "😅‼️",
      "Chat" => "556182098580@s.whatsapp.net"
    },
    "Message" => {
      "conversation" => "teste4000"
    }
  },
  "type" => "Message",
  "phone_number" => "556133712229",
  "instanceName" => "Chatwoot_61 33712229"
}

channel = Channel::Whatsapp.find_by(phone_number: "556133712229")
if channel
  puts "Channel found: #{channel.id} / #{channel.phone_number}"
  service = Whatsapp::IncomingMessageWuzapiService.new(inbox: channel.inbox, params: payload)
  begin
    service.perform
    puts "Service performed successfully."
  rescue StandardError => e
    puts "ERROR: #{e.message}"
    puts e.backtrace.first(10)
  end
else
  puts "Channel not found for 556133712229"
end
