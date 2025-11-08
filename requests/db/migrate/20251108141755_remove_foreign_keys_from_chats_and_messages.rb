class RemoveForeignKeysFromChatsAndMessages < ActiveRecord::Migration[7.1]
  def change
    # Remove foreign key and application_id from chats
    remove_foreign_key :chats, :applications
    remove_index :chats, [:application_id, :number]
    remove_column :chats, :application_id
    
    # Add unique index on token and number for chats
    add_index :chats, [:token, :number], unique: true
    
    # Remove foreign key and chat_id from messages
    remove_foreign_key :messages, :chats
    remove_index :messages, [:chat_id, :number]
    remove_column :messages, :chat_id
    
    # Add unique index on token, chat_number and number for messages
    add_index :messages, [:token, :chat_number, :number], unique: true
  end
end
