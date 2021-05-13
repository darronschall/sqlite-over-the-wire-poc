class CreateAuthorships < ActiveRecord::Migration[6.1]
  def change
    # Do not create a separate id column; this is a join table.
    create_table :authorships, id: false do |t|
      t.belongs_to :author, type: :uuid, null: false, foreign_key: true
      t.belongs_to :book, type: :uuid, null: false, foreign_key: true

      t.timestamps
    end

    # Composite primary key
    add_index :authorships, %i[author_id book_id], unique: true
  end
end
