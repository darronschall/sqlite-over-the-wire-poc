class Book < ApplicationRecord
  self.implicit_order_column = "created_at"

  # @!attribute title
  #   @return [String] the title of the book

  # @!attribute description
  #   @return [String] the description of the book

  # @!attribute published_at
  #   @return [Date] the date when the book was first published

  has_many :authorships
  has_many :authors, through: :authorships

  belongs_to :genre, optional: true
end
