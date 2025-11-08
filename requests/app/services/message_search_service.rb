class MessageSearchService
  def self.search(token, chat_number, query)
    # Try Elasticsearch first if available
    if elasticsearch_available?
      search_with_elasticsearch(token, chat_number, query)
    else
      # Fallback to SQL search
      search_with_sql(token, chat_number, query)
    end
  end

  def self.elasticsearch_available?
    ENV['ELASTICSEARCH_URL'].present? && elasticsearch_client.ping
  rescue StandardError
    false
  end

  def self.search_with_elasticsearch(token, chat_number, query)
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
                term: { token: token }
              },
              {
                term: { chat_number: chat_number }
              }
            ]
          }
        },
        sort: [
          { created_at: { order: 'desc' } }
        ],
        _source: ['number', 'body', 'created_at', 'sender_name']
      }
    )

    # Get all data directly from Elasticsearch
    response['hits']['hits'].map do |hit|
      source = hit['_source']
      OpenStruct.new(
        number: source['number'],
        body: source['body'],
        created_at: source['created_at'],
        sender_name: source['sender_name']
      )
    end
  rescue StandardError => e
    Rails.logger.error("Elasticsearch search failed: #{e.message}")
    search_with_sql(token, chat_number, query)
  end

  def self.search_with_sql(token, chat_number, query)
    Message.where(token: token, chat_number: chat_number)
           .where('messages.body LIKE ?', "%#{query}%")
           .joins(:creator)
           .select('messages.number, messages.body, messages.created_at, users.name as sender_name')
           .order(id: :desc)
  end

  def self.elasticsearch_client
    @elasticsearch_client ||= Elasticsearch::Client.new(
      url: ENV['ELASTICSEARCH_URL'] || 'http://localhost:9200',
      log: false
    )
  end
end
