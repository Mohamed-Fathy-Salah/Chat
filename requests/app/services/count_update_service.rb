class CountUpdateService
  def self.update_chats_count
    # Get all chat counter keys
    keys = REDIS.keys('chat_counter:*')
    
    keys.each do |key|
      token = key.split(':').last
      count = REDIS.get(key).to_i
      
      application = Application.where(token: token).pick(:id)
      next unless application
      
      Application.where(id: application).update_all(chats_count: count)
      Rails.logger.info "Updated chats_count for application #{token}: #{count}"
    end
  end

  def self.update_messages_count
    # Get all message counter keys
    keys = REDIS.keys('message_counter:*')
    
    keys.each do |key|
      parts = key.split(':')
      token = parts[1]
      chat_number = parts[2].to_i
      count = REDIS.get(key).to_i
      
      chat = Chat.where(token: token, number: chat_number).pick(:id)
      next unless chat
      
      Chat.where(id: chat).update_all(messages_count: count)
      Rails.logger.info "Updated messages_count for chat #{token}:#{chat_number}: #{count}"
    end
  end

  def self.update_all_counts
    update_chats_count
    update_messages_count
  end
end
