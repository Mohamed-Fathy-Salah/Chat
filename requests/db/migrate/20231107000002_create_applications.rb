class CreateApplications < ActiveRecord::Migration[7.1]
  def change
    create_table :applications do |t|
      t.string :token, null: false
      t.string :name, null: false
      t.integer :chats_count, default: 0
      t.references :creator, foreign_key: { to_table: :users }

      t.timestamps
    end

    add_index :applications, :token, unique: true
  end
end
