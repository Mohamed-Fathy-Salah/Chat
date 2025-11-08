require 'rails_helper'

RSpec.describe MessageSearchService do
  let(:user) { create(:user) }
  let(:application) { create(:application, creator: user) }
  let(:chat) { create(:chat, application: application, creator: user, token: application.token, number: 1) }

  before do
    create(:message, chat: chat, creator: user, body: 'Hello world', number: 1, token: application.token, chat_number: 1)
    create(:message, chat: chat, creator: user, body: 'Goodbye world', number: 2, token: application.token, chat_number: 1)
    create(:message, chat: chat, creator: user, body: 'Testing message', number: 3, token: application.token, chat_number: 1)
  end

  describe '.search' do
    context 'when Elasticsearch is not available' do
      before do
        allow(MessageSearchService).to receive(:elasticsearch_available?).and_return(false)
      end

      it 'falls back to SQL search' do
        results = MessageSearchService.search(application.token, chat.number, 'Hello')
        expect(results.size).to eq(1)
        expect(results.first.body).to include('Hello')
      end

      it 'searches with case-insensitive LIKE' do
        results = MessageSearchService.search(application.token, chat.number, 'WORLD')
        expect(results.size).to eq(2)
      end

      it 'returns empty array for blank query' do
        results = MessageSearchService.search(application.token, chat.number, '')
        expect(results).to be_empty
      end

      it 'filters by token and chat_number' do
        other_chat = create(:chat, application: application, creator: user, number: 2, token: application.token)
        create(:message, chat: other_chat, creator: user, body: 'Hello from other chat', number: 1, token: application.token, chat_number: 2)
        
        results = MessageSearchService.search(application.token, chat.number, 'Hello')
        expect(results.size).to eq(1)
        expect(results.first.chat_number).to eq(chat.number)
      end
    end

    context 'when Elasticsearch is available' do
      let(:es_client) { instance_double(Elasticsearch::Client) }
      let(:es_response) do
        {
          'hits' => {
            'hits' => [
              {
                '_source' => {
                  'number' => 1,
                  'body' => 'Hello world',
                  'created_at' => Time.current.iso8601,
                  'sender_name' => user.name
                }
              }
            ]
          }
        }
      end

      before do
        allow(MessageSearchService).to receive(:elasticsearch_available?).and_return(true)
        allow(MessageSearchService).to receive(:elasticsearch_client).and_return(es_client)
      end

      it 'searches using Elasticsearch' do
        expect(es_client).to receive(:search).with(
          hash_including(
            index: 'messages',
            body: hash_including(
              query: hash_including(
                bool: hash_including(
                  must: array_including(
                    hash_including(match: hash_including(body: hash_including(query: 'Hello'))),
                    hash_including(term: { token: application.token }),
                    hash_including(term: { chat_number: chat.number })
                  )
                )
              )
            )
          )
        ).and_return(es_response)

        results = MessageSearchService.search(application.token, chat.number, 'Hello')
        expect(results).not_to be_empty
        expect(results.first.body).to eq('Hello world')
      end

      it 'falls back to SQL on Elasticsearch error' do
        allow(es_client).to receive(:search).and_raise(StandardError.new('ES error'))
        
        results = MessageSearchService.search(application.token, chat.number, 'Hello')
        expect(results.size).to eq(1)
      end

      it 'returns empty array for blank query' do
        results = MessageSearchService.search(application.token, chat.number, '')
        expect(results).to eq([])
      end
    end
  end

  describe '.elasticsearch_available?' do
    let(:es_client) { instance_double(Elasticsearch::Client) }

    before do
      allow(MessageSearchService).to receive(:elasticsearch_client).and_return(es_client)
    end

    it 'returns true when Elasticsearch is reachable' do
      allow(ENV).to receive(:[]).with('ELASTICSEARCH_URL').and_return('http://localhost:9200')
      allow(es_client).to receive(:ping).and_return(true)
      
      expect(MessageSearchService.elasticsearch_available?).to be true
    end

    it 'returns false when ELASTICSEARCH_URL is not set' do
      allow(ENV).to receive(:[]).with('ELASTICSEARCH_URL').and_return(nil)
      
      expect(MessageSearchService.elasticsearch_available?).to be false
    end

    it 'returns false when Elasticsearch ping fails' do
      allow(ENV).to receive(:[]).with('ELASTICSEARCH_URL').and_return('http://localhost:9200')
      allow(es_client).to receive(:ping).and_raise(StandardError.new('Connection failed'))
      
      expect(MessageSearchService.elasticsearch_available?).to be false
    end
  end

  describe '.search_with_sql' do
    it 'searches messages by body content' do
      results = MessageSearchService.search_with_sql(application.token, chat.number, 'Testing')
      expect(results.size).to eq(1)
      expect(results.first.body).to include('Testing')
    end

    it 'includes sender name from user join' do
      results = MessageSearchService.search_with_sql(application.token, chat.number, 'Hello')
      expect(results.first.sender_name).to eq(user.name)
    end

    it 'orders by id descending' do
      results = MessageSearchService.search_with_sql(application.token, chat.number, 'world')
      expect(results.first.number).to eq(2) # Goodbye world
      expect(results.last.number).to eq(1) # Hello world
    end

    it 'filters by token' do
      other_app = create(:application, creator: user)
      other_chat = create(:chat, application: other_app, creator: user, token: other_app.token, number: 1)
      create(:message, chat: other_chat, creator: user, body: 'Hello from other app', number: 1, token: other_app.token, chat_number: 1)
      
      results = MessageSearchService.search_with_sql(application.token, chat.number, 'Hello')
      expect(results.size).to eq(1)
    end

    it 'filters by chat_number' do
      other_chat = create(:chat, application: application, creator: user, number: 99, token: application.token)
      create(:message, chat: other_chat, creator: user, body: 'Hello from chat 99', number: 1, token: application.token, chat_number: 99)
      
      results = MessageSearchService.search_with_sql(application.token, chat.number, 'Hello')
      expect(results.size).to eq(1)
      expect(results.first.body).not_to include('chat 99')
    end
  end
end
