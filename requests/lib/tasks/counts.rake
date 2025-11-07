namespace :counts do
  desc 'Update chats and messages counts from Redis'
  task update: :environment do
    puts "Starting count update..."
    CountUpdateService.update_all_counts
    puts "Count update completed."
  end

  desc 'Update chats count from Redis'
  task update_chats: :environment do
    puts "Updating chats count..."
    CountUpdateService.update_chats_count
    puts "Chats count update completed."
  end

  desc 'Update messages count from Redis'
  task update_messages: :environment do
    puts "Updating messages count..."
    CountUpdateService.update_messages_count
    puts "Messages count update completed."
  end
end
