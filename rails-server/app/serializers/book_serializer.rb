class BookSerializer
  include JSONAPI::Serializer

  attributes :title, :description, :published_at
  has_many :authors
  belongs_to :genre
end
