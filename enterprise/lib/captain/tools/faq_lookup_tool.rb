class Captain::Tools::FaqLookupTool < Captain::Tools::BasePublicTool
  description 'Search FAQ responses using semantic similarity to find relevant answers'
  param :query, type: 'string', desc: 'The question or topic to search for in the FAQ database'

  def perform(_tool_context, query:)
    Rails.logger.info "[Captain][FaqLookupTool] Starting search with query: '#{query}'"
    log_tool_usage('searching', { query: query })

    # Use existing vector search on approved responses
    responses = @assistant.responses.approved.search(query).to_a
    Rails.logger.info "[Captain][FaqLookupTool] Query returned #{responses.size} results."

    if responses.empty?
      Rails.logger.info "[Captain][FaqLookupTool] No results found for: #{query}"
      log_tool_usage('no_results', { query: query })
      "No relevant FAQs found for: #{query}"
    else
      Rails.logger.info '[Captain][FaqLookupTool] Found results, formatting...'
      log_tool_usage('found_results', { query: query, count: responses.size })
      format_responses(responses)
    end
  end

  private

  def format_responses(responses)
    responses.map { |response| format_response(response) }.join
  end

  def format_response(response)
    formatted_response = "
        Question: #{response.question}
        Answer: #{response.answer}
        "
    if should_show_source?(response)
      formatted_response += "
          Source: #{response.documentable.external_link}
          "
    end

    formatted_response
  end

  def should_show_source?(response)
    return false if response.documentable.blank?
    return false unless response.documentable.try(:external_link)

    # Don't show source if it's a PDF placeholder
    external_link = response.documentable.external_link
    !external_link.start_with?('PDF:')
  end
end
