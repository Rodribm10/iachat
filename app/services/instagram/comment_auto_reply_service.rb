class Instagram::CommentAutoReplyService
  GRAPH_API_VERSION = 'v22.0'.freeze
  GRAPH_API_BASE = "https://graph.instagram.com/#{GRAPH_API_VERSION}".freeze
  PROCESSING_TTL = 5.minutes.to_i
  PROCESSED_TTL = 30.days.to_i

  DEFAULT_KEYWORD = 'quiz'.freeze
  DEFAULT_PUBLIC_REPLY = 'Vou te mandar o link no DM.'.freeze
  DEFAULT_PRIVATE_REPLY = 'Quer participar do nosso quiz para casais? Segue o link: https://quiz.hoteis1001noites.com.br'.freeze

  def initialize(entry:, change:)
    @entry = entry.with_indifferent_access
    @change = change.with_indifferent_access
  end

  def perform
    return unless eligible_comment?
    return unless acquire_processing_lock!

    send_private_reply!
    mark_processed!
    send_public_reply!
  rescue StandardError => e
    ChatwootExceptionTracker.new(e).capture_exception
    Rails.logger.error("Instagram comment auto-reply failed: #{e.class} - #{e.message}")
  ensure
    release_processing_lock!
  end

  private

  attr_reader :entry, :change

  def eligible_comment?
    channel.present? &&
      comment_id.present? &&
      top_level_comment? &&
      keyword_match? &&
      !processed?
  end

  def channel
    @channel ||= Channel::Instagram.find_by(instagram_id: entry[:id])
  end

  def value
    @value ||= change[:value] || {}
  end

  def comment_id
    value[:id]
  end

  def comment_text
    value[:text].to_s
  end

  def top_level_comment?
    value[:parent_id].blank?
  end

  def keyword_match?
    normalize(comment_text) == normalize(keyword)
  end

  def normalize(text)
    text.to_s.strip.downcase.gsub(/\A[[:punct:]\s]+|[[:punct:]\s]+\z/, '')
  end

  def keyword
    ENV.fetch('INSTAGRAM_COMMENT_AUTOREPLY_KEYWORD', DEFAULT_KEYWORD)
  end

  def public_reply
    ENV.fetch('INSTAGRAM_COMMENT_AUTOREPLY_PUBLIC_REPLY', DEFAULT_PUBLIC_REPLY)
  end

  def private_reply
    ENV.fetch('INSTAGRAM_COMMENT_AUTOREPLY_PRIVATE_REPLY', DEFAULT_PRIVATE_REPLY)
  end

  def processed?
    Redis::Alfred.get(processed_key).present?
  end

  def acquire_processing_lock!
    Redis::Alfred.set(processing_key, true, nx: true, ex: PROCESSING_TTL)
  end

  def release_processing_lock!
    Redis::Alfred.delete(processing_key) if comment_id.present?
  end

  def mark_processed!
    Redis::Alfred.set(processed_key, true, ex: PROCESSED_TTL)
  end

  def processing_key
    "INSTAGRAM_COMMENT_AUTOREPLY_PROCESSING::#{comment_id}"
  end

  def processed_key
    "INSTAGRAM_COMMENT_AUTOREPLY_PROCESSED::#{comment_id}"
  end

  def send_private_reply!
    response = HTTParty.post(
      "#{GRAPH_API_BASE}/#{channel.instagram_id}/messages",
      body: {
        recipient: { comment_id: comment_id },
        message: { text: private_reply }
      }.to_json,
      headers: { 'Content-Type' => 'application/json' },
      query: { access_token: channel.access_token }
    )

    process_response!(response, 'private reply')
  end

  def send_public_reply!
    response = HTTParty.post(
      "#{GRAPH_API_BASE}/#{comment_id}/replies",
      body: { message: public_reply }.to_json,
      headers: { 'Content-Type' => 'application/json' },
      query: { access_token: channel.access_token }
    )

    process_response!(response, 'public reply')
  end

  def process_response!(response, operation)
    parsed_response = response.parsed_response || {}
    return parsed_response if response.success? && parsed_response['error'].blank?

    error_code = parsed_response.dig('error', 'code')
    channel.authorization_error! if error_code == 190

    error_message = parsed_response.dig('error', 'message') || response.body
    raise StandardError, "#{operation} failed: #{response.code} - #{error_message}"
  end
end
