class Author < ApplicationRecord
  self.implicit_order_column = "created_at"

  # @!attribute first_name
  #   @return [String] the first name of the author

  # @!attribute last_name
  #   @return [String] the last name of the author

  has_many :authorships
  has_many :books, through: :authorships
end
