module API
  module V1
    class BooksController < ApplicationController
      # GET /books
      def index
        @books = Book.all.includes([:genre, authorships: :author])

        respond_to do |format|
          format.sqlite3 do
            tmpfile = create_sqlite_db(@books)

            File.open(tmpfile.path, "r") do |file|
              send_data file.read, type: :sqlite3
            end

            tmpfile.delete
          rescue => e
            puts e
          end
          format.json do
            render json: BookSerializer.new(@books, include: %w[authors genre authors.books]).serializable_hash
          end
        end
      end

      private

      def create_sqlite_db(books)
        tmp_file = Tempfile.new("test", Rails.root.join("tmp"))
        # TODO: Explore using ":memory:" to improve performance.
        db = SQLite3::Database.new tmp_file.path

        create_schema(db)

        # TODO: Externalize serialization; Leverage serializers or perhaps existing ActiveModel directly?
        books.each do |book|
          db.execute "INSERT OR IGNORE INTO genres VALUES(?, ?, ?)", [book.genre.id, book.genre.title, book.genre.description]
          db.execute "INSERT INTO books VALUES(?, ?, ?, ?, ?)", [book.id, book.title, book.description, book.published_at.to_s, book.genre.id]
          book.authors.each do |author|
            db.execute "INSERT OR IGNORE INTO authors VALUES(?, ?, ?)", [author.id, author.first_name, author.last_name]
            db.execute "INSERT INTO authorships VALUES(?, ?)", [author.id, book.id]
          end
        end

        db.close

        tmp_file.close
        tmp_file
      end

      def create_schema(db)
        # TODO: Externalize schema; Possibly re-use schema.rb DSL
        db.execute "CREATE TABLE genres(id CHARACTER(36) PRIMARY KEY, title TEXT, description TEXT);"
        db.execute "CREATE TABLE books(id CHARACTER(36) PRIMARY KEY, title TEXT, description TEXT, published_at DATE, genre_id CHARACTER(36), FOREIGN KEY(genre_id) REFERENCES genres(id));"
        db.execute "CREATE TABLE authors(id CHARACTER(36) PRIMARY KEY, first_name TEXT, last_name TEXT);"
        db.execute "CREATE TABLE authorships(author_id CHARACTER(36), book_id CHARACTER(36), PRIMARY KEY(author_id, book_id), FOREIGN KEY(author_id) REFERENCES authors(id), FOREIGN KEY(book_id) REFERENCES books(id));"
      end
    end
  end
end
