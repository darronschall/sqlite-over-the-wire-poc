class CreateBooks < ActiveRecord::Migration[6.1]
  def change
    create_table :books, id: :uuid do |t|
      t.string :title
      t.string :description

      t.datetime :published_at

      t.timestamps
    end
  end
end
