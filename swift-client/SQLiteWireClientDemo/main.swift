//
//  main.swift
//  SQLiteWireClientDemo
//
//  Created by Darron Schall on 5/13/21.
//

import Foundation
import SQLite3

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
        let start = DispatchTime.now()

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

        let end = DispatchTime.now()
        let nanoTime = end.uptimeNanoseconds - start.uptimeNanoseconds
        let timeInterval = Double(nanoTime) / 1_000_000_000
        print("json parsing time: \(timeInterval)")

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

// MARK: Fetch and process SQLite3 API response

func getBooksAsSQLite3(completionHandler: @escaping () -> Void) {
    let url = URL(string: "http://127.0.0.1:3000/api/v1/books")!
    var urlRequest = URLRequest(url: url)
    urlRequest.httpMethod = "GET"
    urlRequest.setValue("application/x-sqlite3", forHTTPHeaderField: "Accept")

    let session = URLSession(configuration: URLSessionConfiguration.default)
    let task = session.dataTask(with: urlRequest) { data, response, error in
        let start = DispatchTime.now()

        guard let data = data, error == nil else {
            fatalError ("error: \(error!)")
        }

        let path = FileManager.default.currentDirectoryPath
        let tempDatabaseUrl = URL(string: "file://\(path)")!.appendingPathComponent("temp_data.sqlite")

        if FileManager.default.fileExists(atPath: tempDatabaseUrl.path) {
            try! FileManager.default.removeItem(at: tempDatabaseUrl)
        }

        try! data.write(to: tempDatabaseUrl)

        var db: OpaquePointer?
        if sqlite3_open(tempDatabaseUrl.path, &db) != SQLITE_OK { // error mostly because of corrupt database
            fatalError("error opening database \(tempDatabaseUrl.absoluteString)")
        }

        populateGenres(from: db!)
        populateBooks(from: db!)
        populateAuthors(from: db!)
        populateAuthorships(from: db!)

        if sqlite3_close(db) != SQLITE_OK {
            fatalError("error closing database \(tempDatabaseUrl.absoluteString)")
        }

        try! FileManager.default.removeItem(at: tempDatabaseUrl)

        let end = DispatchTime.now()
        let nanoTime = end.uptimeNanoseconds - start.uptimeNanoseconds
        let timeInterval = Double(nanoTime) / 1_000_000_000
        print("sqlite parsing time: \(timeInterval)")

        completionHandler()
    }
    task.resume()
}

func populateGenres(from db: OpaquePointer) {
    let genresQuerySql = "SELECT * FROM genres;"
    var queryStatement: OpaquePointer?
    if sqlite3_prepare_v2(db, genresQuerySql, -1, &queryStatement, nil) == SQLITE_OK {
        while (sqlite3_step(queryStatement) == SQLITE_ROW) {
            let id = String(cString: sqlite3_column_text(queryStatement, 0)!)
            let title = String(cString: sqlite3_column_text(queryStatement, 1)!)
            let description = String(cString: sqlite3_column_text(queryStatement, 2)!)

            let genre = Genre(id: UUID(uuidString: id)!)
            genre.title = title
            genre.description = description
            genre.books = [] // We'll populate this whe we process Books
            genres.append(genre)
        }
    } else {
        let errorMessage = String(cString: sqlite3_errmsg(db))
        print("\nError populating genres: query is not prepared \(errorMessage)")
    }
    sqlite3_finalize(queryStatement)
}

func populateBooks(from db: OpaquePointer) {
    let booksQuerySql = "SELECT * FROM books;"
    var queryStatement: OpaquePointer?
    if sqlite3_prepare_v2(db, booksQuerySql, -1, &queryStatement, nil) == SQLITE_OK {
        while (sqlite3_step(queryStatement) == SQLITE_ROW) {
            let id = String(cString: sqlite3_column_text(queryStatement, 0)!)
            let title = String(cString: sqlite3_column_text(queryStatement, 1)!)
            let description = String(cString: sqlite3_column_text(queryStatement, 2)!)
            let publishedAt = String(cString: sqlite3_column_text(queryStatement, 3)!)
            let genreId = String(cString: sqlite3_column_text(queryStatement, 4)!)

            let book = Book(id: UUID(uuidString: id)!)
            book.title = title
            book.description = description
            book.publishedAt = dateFormatter.date(from: publishedAt)
            // We know that all Genres are already loaded at this point
            book.genre = findById(array: genres, id: genreId)
            book.authors = [] // We'll populate this later via authorships
            books.append(book)

            // Create the circular reference while we're here
            book.genre!.books!.append(book)
        }
    } else {
        let errorMessage = String(cString: sqlite3_errmsg(db))
        print("\nError populating books: query is not prepared \(errorMessage)")
    }
    sqlite3_finalize(queryStatement)
}

func populateAuthors(from db: OpaquePointer) {
    let authorsQuerySql = "SELECT * FROM authors;"
    var queryStatement: OpaquePointer?
    if sqlite3_prepare_v2(db, authorsQuerySql, -1, &queryStatement, nil) == SQLITE_OK {
        while (sqlite3_step(queryStatement) == SQLITE_ROW) {
            let id = String(cString: sqlite3_column_text(queryStatement, 0)!)
            let firstName = String(cString: sqlite3_column_text(queryStatement, 1)!)
            let lastName = String(cString: sqlite3_column_text(queryStatement, 2)!)

            let author = Author(id: UUID(uuidString: id)!)
            author.firstName = firstName
            author.lastName = lastName
            author.books = [] // We'll populate this later via authorships
            authors.append(author)
        }
    } else {
        let errorMessage = String(cString: sqlite3_errmsg(db))
        print("\nError populating authors: query is not prepared \(errorMessage)")
    }
    sqlite3_finalize(queryStatement)
}

func populateAuthorships(from db: OpaquePointer) {
    let authorshipsQuerySql = "SELECT * FROM authorships;"
    var queryStatement: OpaquePointer?
    if sqlite3_prepare_v2(db, authorshipsQuerySql, -1, &queryStatement, nil) == SQLITE_OK {
        while (sqlite3_step(queryStatement) == SQLITE_ROW) {
            let authorId = String(cString: sqlite3_column_text(queryStatement, 0)!)
            let bookId = String(cString: sqlite3_column_text(queryStatement, 1)!)

            let author = findById(array: authors, id: authorId)!
            let book = findById(array: books, id: bookId)!

            author.books!.append(book)
            book.authors!.append(author)
        }
    } else {
        let errorMessage = String(cString: sqlite3_errmsg(db))
        print("\nError populating authorships: query is not prepared \(errorMessage)")
    }
    sqlite3_finalize(queryStatement)
}

// MARK: Timer helper

func measureElapsedTime(_ closure: (@escaping () -> Void) -> Void) {
    // Re-set to pristine post-processing internal object graph
    genres = []
    books = []
    authors = []

    // Keep alive to wait for the results of the processing
    let semaphore = DispatchSemaphore(value: 0)

    let start = DispatchTime.now()

    closure {
        semaphore.signal()
    }
    semaphore.wait()

    let end = DispatchTime.now()
    let nanoTime = end.uptimeNanoseconds - start.uptimeNanoseconds
    let timeInterval = Double(nanoTime) / 1_000_000_000
    print("elapsed time: \(timeInterval)")
}

// MARK: Main

for _ in 0..<10 {
    measureElapsedTime(getBooksAsJSON)
}

print("----------")

for _ in 0..<10 {
    measureElapsedTime(getBooksAsSQLite3)
}
