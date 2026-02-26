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
  "phone_number" => "556191544165",
  "instanceName" => "Chatwoot_556191544165"
}

phone = "556191544165"
channel = Channel::Whatsapp.find_by(phone_number: phone) ||
          Channel::Whatsapp.find_by(phone_number: "+#{phone}") ||
          Channel::Whatsapp.where("regexp_replace(phone_number, '[^0-9]', '', 'g') = ?", phone).first

if channel
  puts "Channel found: #{channel.id} / #{channel.phone_number}"
  service = Whatsapp::IncomingMessageWuzapiService.new(inbox: channel.inbox, params: payload)
  begin
    service.perform
    puts "Service performed successfully."
    puts "Last conversation: #{channel.inbox.conversations.last&.id}"
    puts "Last message: #{channel.inbox.messages.last&.content}"
  rescue StandardError => e
    puts "ERROR: #{e.message}"
    puts e.backtrace.first(10)
  end
else
  puts "Channel still not found for #{phone}."
end
