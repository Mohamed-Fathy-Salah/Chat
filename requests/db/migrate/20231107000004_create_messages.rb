class CreateMessages < ActiveRecord::Migration[7.1]
  def change
    create_table :messages do |t|
      t.references :chat, null: false, foreign_key: true
      t.string :token
      t.integer :chat_number
      t.integer :number, null: false
      t.text :body, null: false
      t.references :creator, foreign_key: { to_table: :users }

      t.timestamps
    end

    add_index :messages, [:chat_id, :number], unique: true
    add_index :messages, :token
    add_index :messages, :chat_number
  end
end
