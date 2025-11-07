namespace :auth do
  desc "Rotate the authentication secret key stored in Redis"
  task rotate_secret_key: :environment do
    puts "Rotating secret key..."
    AuthenticationService.rotate_secret_key!
    puts "Secret key rotated successfully at #{Time.current}"
  end

  desc "Check if secret key needs rotation (runs every 2 days via cron)"
  task check_and_rotate: :environment do
    last_rotation = Redis.current.get("auth_secret_key:last_rotation")&.to_i || 0
    current_time = Time.current.to_i
    
    if current_time - last_rotation > 2.days.to_i
      puts "Secret key is older than 2 days, rotating..."
      AuthenticationService.rotate_secret_key!
      Redis.current.set("auth_secret_key:last_rotation", current_time)
      puts "Secret key rotated successfully"
    else
      puts "Secret key is still fresh (last rotated #{Time.at(last_rotation)})"
    end
  end
end
