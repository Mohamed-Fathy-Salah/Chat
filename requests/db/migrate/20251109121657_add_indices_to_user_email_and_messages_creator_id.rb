class AddIndicesToUserEmailAndMessagesCreatorId < ActiveRecord::Migration[7.1]
  def change
    # Add index on users.email if it doesn't exist
    # (It should already exist from create_users migration, but this ensures it)
    unless index_exists?(:users, :email)
      add_index :users, :email, unique: true
    end
    
    # Add index on messages.creator_id for faster lookups
    # This improves performance for queries filtering/joining by creator
    unless index_exists?(:messages, :creator_id)
      add_index :messages, :creator_id
    end
  end
end
