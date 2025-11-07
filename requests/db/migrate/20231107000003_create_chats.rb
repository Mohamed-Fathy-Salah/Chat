class CreateChats < ActiveRecord::Migration[7.1]
  def change
    create_table :chats do |t|
      t.references :application, null: false, foreign_key: true
      t.string :token
      t.integer :number, null: false
      t.string :title
      t.integer :messages_count, default: 0
      t.references :creator, foreign_key: { to_table: :users }

      t.timestamps
    end

    add_index :chats, [:application_id, :number], unique: true
    add_index :chats, :token
  end
end
