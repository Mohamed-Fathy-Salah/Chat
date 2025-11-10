namespace :elasticsearch do
  desc 'Reindex all messages to Elasticsearch'
  task reindex_messages: :environment do
    require 'elasticsearch'
    
    client = Elasticsearch::Client.new(
      url: ENV['ELASTICSEARCH_URL'] || 'http://localhost:9200',
      log: false
    )
    
    puts "Starting message reindexing..."
    
    total = Message.count
    indexed = 0
    errors = 0
    
    Message.includes(:creator).find_each.with_index do |message, index|
      begin
        doc = {
          id: message.id,
          token: message.token,
          chat_number: message.chat_number,
          number: message.number,
          body: message.body,
          sender_id: message.creator_id,
          sender_name: message.creator&.name,
          created_at: message.created_at.iso8601
        }
        
        doc_id = "#{message.token}:#{message.chat_number}:#{message.number}"
        
        client.index(
          index: 'messages',
          id: doc_id,
          body: doc
        )
        
        indexed += 1
        print "\rIndexed #{indexed}/#{total} messages..." if (index + 1) % 10 == 0
      rescue => e
        errors += 1
        puts "\nError indexing message #{message.id}: #{e.message}"
      end
    end
    
    puts "\n\nReindexing complete!"
    puts "Total: #{total}"
    puts "Indexed: #{indexed}"
    puts "Errors: #{errors}"
  end
  
  desc 'Delete and recreate Elasticsearch index'
  task reset_index: :environment do
    require 'elasticsearch'
    
    client = Elasticsearch::Client.new(
      url: ENV['ELASTICSEARCH_URL'] || 'http://localhost:9200',
      log: false
    )
    
    begin
      puts "Deleting messages index..."
      client.indices.delete(index: 'messages')
      puts "Index deleted."
    rescue Elasticsearch::Transport::Transport::Errors::NotFound
      puts "Index doesn't exist, skipping delete."
    rescue Elastic::Transport::Transport::Errors::NotFound
      puts "Index doesn't exist, skipping delete."
    end
    
    sleep 3
    
    puts "Creating messages index with n-gram support..."
    begin
      client.indices.create(
        index: 'messages',
        body: {
        settings: {
          analysis: {
            analyzer: {
              ngram_analyzer: {
                type: 'custom',
                tokenizer: 'standard',
                filter: ['lowercase', 'ngram_filter']
              },
              search_analyzer: {
                type: 'custom',
                tokenizer: 'standard',
                filter: ['lowercase']
              }
            },
            filter: {
              ngram_filter: {
                type: 'edge_ngram',
                min_gram: 3,
                max_gram: 20
              }
            }
          }
        },
        mappings: {
          properties: {
            id: { type: 'integer' },
            chat_id: { type: 'integer' },
            token: { type: 'keyword' },
            chat_number: { type: 'integer' },
            number: { type: 'integer' },
            body: { 
              type: 'text',
              analyzer: 'ngram_analyzer',
              search_analyzer: 'search_analyzer',
              fields: {
                keyword: { type: 'keyword' },
                exact: { type: 'text', analyzer: 'standard' }
              }
            },
            sender_id: { type: 'integer' },
            sender_name: { type: 'keyword' },
            created_at: { type: 'date' }
          }
        }
      }
      )
      puts "Index created."
    rescue Elastic::Transport::Transport::Errors::BadRequest => e
      if e.message.include?('already exists')
        puts "Index already exists, skipping creation."
      else
        raise
      end
    end
    
    puts "\nNow run: rake elasticsearch:reindex_messages"
  end
  
  desc 'Show Elasticsearch stats'
  task stats: :environment do
    require 'elasticsearch'
    
    client = Elasticsearch::Client.new(
      url: ENV['ELASTICSEARCH_URL'] || 'http://localhost:9200',
      log: false
    )
    
    begin
      count = client.count(index: 'messages')['count']
      mysql_count = Message.count
      
      puts "Messages in MySQL: #{mysql_count}"
      puts "Messages in Elasticsearch: #{count}"
      puts "Missing from ES: #{mysql_count - count}"
    rescue => e
      puts "Error: #{e.message}"
    end
  end
end
