class CountUpdateService
  def self.update_chats_count
    # Get all chat counter keys
    keys = REDIS.keys('chat_counter:*')
    
    keys.each do |key|
      token = key.split(':').last
      count = REDIS.get(key).to_i
      
      application = Application.find_by(token: token)
      next unless application
      
      application.update_column(:chats_count, count)
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
      
      application = Application.find_by(token: token)
      next unless application
      
      chat = application.chats.find_by(number: chat_number)
      next unless chat
      
      chat.update_column(:messages_count, count)
      Rails.logger.info "Updated messages_count for chat #{token}:#{chat_number}: #{count}"
    end
  end

  def self.update_all_counts
    update_chats_count
    update_messages_count
  end
end
