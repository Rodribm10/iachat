class Captain::OpenAiMessageBuilderService
  require 'base64'
  pattr_initialize [:message!]

  def self.extract_text_and_attachments(content)
    raw_content = content.is_a?(RubyLLM::Content::Raw) ? content.value : content
    return [raw_content, []] unless raw_content.is_a?(Array)

    text_parts = raw_content.select { |part| part[:type] == 'text' }.pluck(:text)
    image_urls = raw_content.select { |part| part[:type] == 'image_url' }.filter_map { |part| part.dig(:image_url, :url) }
    [text_parts.join(' ').presence, image_urls]
  end

  def generate_content
    parts = []
    parts << text_part(@message.content) if @message.content.present?
    parts.concat(attachment_parts(@message.attachments)) if @message.attachments.any?

    return 'Message without content' if parts.blank?
    return parts.first[:text] if parts.one? && parts.first[:type] == 'text'

    RubyLLM::Content::Raw.new(parts)
  end

  def generate_text_content
    content = generate_content
    return content if content.is_a?(String)

    raw_parts = content.is_a?(RubyLLM::Content::Raw) ? content.value : content
    return '' unless raw_parts.is_a?(Array)

    raw_parts.map do |part|
      part[:type] == 'text' ? part[:text] : "[#{part[:type]}]"
    end.join("\n")
  end

  private

  def text_part(text)
    { type: 'text', text: text }
  end

  def image_part(image_url)
    { type: 'image_url', image_url: { url: image_url } }
  end

  def attachment_parts(attachments)
    image_attachments = attachments.where(file_type: :image)
    image_content = image_parts(image_attachments)

    transcription = extract_audio_transcriptions(attachments)
    transcription_part = text_part(transcription) if transcription.present?

    attachment_part = text_part('User has shared an attachment') if attachments.where.not(file_type: %i[image audio]).exists?

    [image_content, transcription_part, attachment_part].flatten.compact
  end

  def image_parts(image_attachments)
    image_attachments.each_with_object([]) do |attachment, parts|
      url = get_attachment_url(attachment)
      parts << image_part(url) if url.present?
    end
  end

  def get_attachment_url(attachment)
    if attachment.file.attached? && attachment.file.image?
      begin
        return "data:#{attachment.file.content_type};base64,#{encode_image(attachment)}"
      rescue StandardError => e
        Rails.logger.error "[Captain::OpenAiMessageBuilderService] Failed to encode image to Base64: #{e.message}"
      end
    end

    return attachment.download_url if attachment.download_url.present?
    return attachment.external_url if attachment.external_url.present?

    attachment.file.attached? ? attachment.file_url : nil
  end

  def encode_image(attachment)
    attachment.file.blob.open do |file|
      Base64.strict_encode64(file.read)
    end
  end

  def extract_audio_transcriptions(attachments)
    audio_attachments = attachments.where(file_type: :audio)
    return '' if audio_attachments.blank?

    audio_attachments.map do |attachment|
      result = Messages::AudioTranscriptionService.new(attachment).perform
      result[:success] ? result[:transcriptions] : ''
    rescue StandardError => e
      Rails.logger.error "[Captain::OpenAiMessageBuilderService] Failed to extract audio transcription: #{e.message}"
      ''
    end.join
  end
end
