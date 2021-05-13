class Genre < ApplicationRecord
  self.implicit_order_column = "created_at"

  # @!attribute title
  #   @return [String] the title of the genre

  # @!attribute description
  #   @return [String] the description of the genre

  has_many :books, dependent: :nullify
end
