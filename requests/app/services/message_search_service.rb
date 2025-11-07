class MessageSearchService
  def self.search(chat, query)
    # Try Elasticsearch first if available
    if elasticsearch_available?
      search_with_elasticsearch(chat, query)
    else
      # Fallback to SQL search
      search_with_sql(chat, query)
    end
  end

  def self.elasticsearch_available?
    # TODO: Check if Elasticsearch is configured and available
    false
  end

  def self.search_with_elasticsearch(chat, query)
    # TODO: Implement Elasticsearch search
    # This would use the Elasticsearch gem to search indexed messages
    []
  end

  def self.search_with_sql(chat, query)
    chat.messages
        .where('body LIKE ?', "%#{query}%")
        .select(:number, :body, :created_at)
        .order(created_at: :desc)
  end
end
