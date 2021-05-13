class GenreSerializer
  include JSONAPI::Serializer

  attributes :title, :description
  has_many :books
end
