//
//  main.swift
//  SQLiteWireClientDemo
//
//  Created by Darron Schall on 5/13/21.
//

import Foundation

// MARK: Post-Processed Data Structures

// Use classes instead of structs for reference semantics, to make it easier to construct
// our circular object graph with partial objects that later get fleshed out as more
// data becomes available.

protocol HasUUIDIdentifier {
    var id: UUID{  get set }
}

class Genre: HasUUIDIdentifier {
    var id: UUID
    var title: String?
    var description: String?
    var books: [Book]?

    init(id: UUID) {
        self.id = id
    }
}

class Book: HasUUIDIdentifier {
    var id: UUID
    var title: String?
    var description: String?
    var genre: Genre?
    var authors: [Author]?
    var publishedAt: Date?

    init(id: UUID) {
        self.id = id
    }
}

class Author: HasUUIDIdentifier {
    var id: UUID
    var firstName: String?
    var lastName: String?
    var books: [Book]?

    init(id: UUID) {
        self.id = id
    }
}

// MARK: Target data structures to populate from the server API response

// Using top-level variables like this isn't a real-world scenario. But, for comparison sake,
// we'll parse the server response into these top-level arrays and build a circular nested
// object graph that represents the data we get back from the server.
//
// We time how long each approach takes to build this in-memory data representation in
// an attempt to compare apples-to-apples across JSON and SQLite data transfer formats.
var genres: [Genre] = []
var books: [Book] = []
var authors: [Author] = []

// Helper for JSON:API parsing to handle partial objects due to relationships/includes
// in the data transfer format. Find an existing that we can link to and/or flesh out.
func findById<T: HasUUIDIdentifier>(array: [T], id: String) -> T? {
    return findById(array: array, id: UUID(uuidString: id)!)
}

func findById<T: HasUUIDIdentifier>(array: [T], id: UUID) -> T? {
    for element in array {
        if element.id == id {
            return element
        }
    }

    return nil
}

// MARK: JSON-API decoding

struct JSONAPIResponse: Decodable {
    var data: [JSONAPIResource]
    var included: [JSONAPIResource]?

    private enum CodingKeys : String, CodingKey { case data, included }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // data is either an array of JSONAPIResource or a single JSONAPIResource
        do {
            data = try container.decode([JSONAPIResource].self, forKey: .data)
        } catch DecodingError.typeMismatch {
            data = [try container.decode(JSONAPIResource.self, forKey: .data)]
        }
        included = try container.decodeIfPresent([JSONAPIResource].self, forKey: .included)
    }
}

struct JSONAPIResource: Decodable {
    var type: String
    var id: String
    var attributes: [String: JSONValue]?
    var relationships: [String: JSONAPIResponse]?
}

enum JSONValue: Decodable {
    case number(Double)
    case integer(Int)
    case string(String)
    case bool(Bool)
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let int = try? container.decode(Int.self) {
            self = .integer(int)
        } else if let double = try? container.decode(Double.self) {
            self = .number(double)
        } else if let string = try? container.decode(String.self) {
            // TODO: Add a .date case and auto-convert if string matches date format
            self = .string(string)
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if container.decodeNil() {
            self = .null
        } else {
            throw DecodingError.typeMismatch(JSONValue.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unrecognized type"))
        }
    }
}

// MARK: Date format helper

// We'll use this to convert strings to Date instances for both JSON and SQLite
let dateFormatter = DateFormatter()
dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"

// MARK: Fetch and process JSON API response

func getBooksAsJSON(completionHandler: @escaping () -> Void) {
    let url = URL(string: "http://127.0.0.1:3000/api/v1/books")!
    var urlRequest = URLRequest(url: url)
    urlRequest.httpMethod = "GET"
    urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")

    let session = URLSession(configuration: URLSessionConfiguration.default)
    let task = session.dataTask(with: urlRequest) { data, response, error in
        guard let data = data, error == nil else {
            fatalError ("error: \(error!)")
        }

        let response = try! JSONDecoder().decode(JSONAPIResponse.self, from: data)
        response.data.forEach { resource in
            _ = processResource(resource: resource)
        }
        response.included?.forEach { resource in
            _ = processResource(resource: resource)
        }

        completionHandler()
    }
    task.resume()
}

func processResource(resource: JSONAPIResource) -> HasUUIDIdentifier {
    switch resource.type {
        case "genre":
            return processGenre(resource: resource)
        case "book":
            return processBook(resource: resource)
        case "author":
            return processAuthor(resource: resource)
        default:
            fatalError("Unexpected type: \(resource.type)")
    }
}

func processGenre(resource: JSONAPIResource) -> Genre {
    // Check to see if our top-level object graph already has this genre
    var genre: Genre? = findById(array: genres, id: resource.id)
    if genre == nil {
        genre = Genre(id: UUID(uuidString: resource.id)!)
        genres.append(genre!)
    }

    // Optionally set attributes because they might not be present if
    // we're processing an included or nested relationship resource
    if case .string(let value) = resource.attributes?["title"] {
        genre!.title = value
    }

    if case .string(let value) = resource.attributes?["description"] {
        genre!.description = value
    }

    if let relationships = resource.relationships {
        if let books = relationships["books"] {
            books.data.forEach { resource in
                let book = processResource(resource: resource) as! Book
                if genre!.books == nil {
                    genre?.books = [book]
                } else {
                    // Only add book if the relationship is not already present
                    if findById(array: genre!.books!, id: book.id) == nil {
                        genre!.books!.append(book)
                    }
                }
            }
        }
    }

    return genre!
}

func processBook(resource: JSONAPIResource) -> Book {
    // Check to see if our top-level object graph already has this book
    var book: Book? = findById(array: books, id: resource.id)
    if book == nil {
        book = Book(id: UUID(uuidString: resource.id)!)
        books.append(book!)
    }

    // Optionally set attributes because they might not be present if
    // we're processing an included or nested relationship resource
    if case .string(let value) = resource.attributes?["title"] {
        book!.title = value
    }

    if case .string(let value) = resource.attributes?["description"] {
        book!.description = value
    }

    if case .string(let value) = resource.attributes?["published_at"] {
        book!.publishedAt = dateFormatter.date(from: value)
    }

    if let relationships = resource.relationships {
        if let authors = relationships["authors"] {
            authors.data.forEach { resource in
                let author = processResource(resource: resource) as! Author
                if book!.authors == nil {
                    book?.authors = [author]
                } else {
                    // Only add author if the relationship is not already present
                    if findById(array: book!.authors!, id: author.id) == nil {
                        book!.authors!.append(author)
                    }
                }
            }
        }

        if let genre = relationships["genre"] {
            genre.data.forEach { resource in
                let genre = processResource(resource: resource) as! Genre
                book!.genre = genre
            }
        }
    }

    return book!
}

func processAuthor(resource: JSONAPIResource) -> Author {
    // Check to see if our top-level object graph already has this author
    var author: Author? = findById(array: authors, id: resource.id)
    if author == nil {
        author = Author(id: UUID(uuidString: resource.id)!)
        authors.append(author!)
    }

    // Optionally set attributes because they might not be present if
    // we're processing an included or nested relationship resource
    if case .string(let value) = resource.attributes?["first_name"] {
        author!.firstName = value
    }

    if case .string(let value) = resource.attributes?["last_name"] {
        author!.lastName = value
    }

    if let relationships = resource.relationships {
        if let books = relationships["books"] {
            books.data.forEach { resource in
                let book = processResource(resource: resource) as! Book
                if author!.books == nil {
                    author?.books = [book]
                } else {
                    // Only add book if the relationship is not already present
                    if findById(array: author!.books!, id: book.id) == nil {
                        author!.books!.append(book)
                    }
                }
            }
        }
    }

    return author!
}

// MARK: Main

let semaphore = DispatchSemaphore.init(value: 0)
getBooksAsJSON {
    semaphore.signal()
}
// Wait for the async call to complete before program terminates
semaphore.wait()
