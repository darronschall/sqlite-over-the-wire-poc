class CreateGenres < ActiveRecord::Migration[6.1]
  def change
    create_table :genres, id: :uuid do |t|
      t.string :title
      t.string :description

      t.timestamps
    end

    add_belongs_to :books, :genre, type: :uuid, foreign_key: true
  end
end
