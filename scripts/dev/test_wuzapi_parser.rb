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
  "phone_number" => "556133712229"
}
parser = Whatsapp::Providers::Wuzapi::PayloadParser.new(payload)
puts "Message Type: #{parser.message_type}"
puts "Text: #{parser.text_content}"
puts "From Me: #{parser.from_me?}"
puts "Sender: #{parser.sender_phone_number}"
