module API
  module V1
    class BooksController < ApplicationController
      # GET /books
      def index
        @books = Book.all.includes([:genre, authorships: :author])

        render json: BookSerializer.new(@books, include: %w[authors genre authors.books]).serializable_hash
      end
    end
  end
end
