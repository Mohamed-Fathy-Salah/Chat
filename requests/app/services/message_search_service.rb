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
    ENV['ELASTICSEARCH_URL'].present? && elasticsearch_client.ping
  rescue StandardError
    false
  end

  def self.search_with_elasticsearch(chat, query)
    return [] if query.blank?

    response = elasticsearch_client.search(
      index: 'messages',
      body: {
        query: {
          bool: {
            must: [
              {
                match: {
                  body: {
                    query: query,
                    operator: 'and',
                    fuzziness: 'AUTO'
                  }
                }
              },
              {
                term: {
                  chat_id: chat.id
                }
              }
            ]
          }
        },
        sort: [
          { created_at: { order: 'desc' } }
        ]
      }
    )

    message_ids = response['hits']['hits'].map { |hit| hit['_source']['id'] }
    return [] if message_ids.empty?

    messages = chat.messages.where(id: message_ids)
                    .select(:id, :number, :body, :created_at)
    
    # Preserve Elasticsearch order
    messages_hash = messages.index_by(&:id)
    message_ids.map { |id| messages_hash[id] }.compact
  rescue StandardError => e
    Rails.logger.error("Elasticsearch search failed: #{e.message}")
    search_with_sql(chat, query)
  end

  def self.search_with_sql(chat, query)
    chat.messages
        .where('body LIKE ?', "%#{query}%")
        .select(:number, :body, :created_at)
        .order(created_at: :desc)
  end

  def self.elasticsearch_client
    @elasticsearch_client ||= Elasticsearch::Client.new(
      url: ENV['ELASTICSEARCH_URL'] || 'http://localhost:9200',
      log: false
    )
  end
end
