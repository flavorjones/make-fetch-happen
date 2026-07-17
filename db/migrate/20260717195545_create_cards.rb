class CreateCards < ActiveRecord::Migration[8.1]
  def change
    create_table :cards do |t|
      t.string :artifact_url, null: false
      t.integer :fizzy_card_number, null: false
      t.string :title

      t.timestamps
    end
    add_index :cards, :artifact_url, unique: true
    add_index :cards, :fizzy_card_number, unique: true
  end
end
