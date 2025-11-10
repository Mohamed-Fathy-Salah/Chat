class MessageSearchService
  def self.search(token, chat_number, query, page = 1, limit = 10)
    # Try Elasticsearch first if available
    if elasticsearch_available?
      search_with_elasticsearch(token, chat_number, query, page, limit)
    else
      # Fallback to SQL search
      search_with_sql(token, chat_number, query, page, limit)
    end
  end

  def self.elasticsearch_available?
    ENV['ELASTICSEARCH_URL'].present? && elasticsearch_client.ping
  rescue StandardError
    false
  end

  def self.search_with_elasticsearch(token, chat_number, query, page, limit)
    return [] if query.blank?

    offset = (page - 1) * limit

    response = elasticsearch_client.search(
      index: 'messages',
      body: {
        query: {
          bool: {
            must: [
              {
                bool: {
                  should: [
                    # Exact match on standard analyzer (highest priority)
                    {
                      match: {
                        'body.exact': {
                          query: query,
                          boost: 4
                        }
                      }
                    },
                    # Partial word matching with n-grams
                    {
                      match: {
                        body: {
                          query: query,
                          boost: 3
                        }
                      }
                    },
                    # Fuzzy matching for typos
                    {
                      match: {
                        'body.exact': {
                          query: query,
                          fuzziness: 'AUTO',
                          boost: 2
                        }
                      }
                    },
                    # Wildcard for contains matching
                    {
                      wildcard: {
                        'body.keyword': {
                          value: "*#{query.downcase}*",
                          boost: 1,
                          case_insensitive: true
                        }
                      }
                    }
                  ],
                  minimum_should_match: 1
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
          { _score: { order: 'desc' } },
          { created_at: { order: 'desc' } }
        ],
        from: offset,
        size: limit,
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
    search_with_sql(token, chat_number, query, page, limit)
  end

  def self.search_with_sql(token, chat_number, query, page, limit)
    offset = (page - 1) * limit

    Message.where(token: token, chat_number: chat_number)
           .where('messages.body LIKE ?', "%#{query}%")
           .joins(:creator)
           .select('messages.number, messages.body, messages.created_at, users.name as sender_name')
           .order(id: :desc)
           .limit(limit)
           .offset(offset)
  end

  def self.elasticsearch_client
    @elasticsearch_client ||= Elasticsearch::Client.new(
      url: ENV['ELASTICSEARCH_URL'] || 'http://localhost:9200',
      log: false
    )
  end
end
