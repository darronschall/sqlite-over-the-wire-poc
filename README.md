# SQLite3 wire protocol Proof-of-Concept

This technical proof-of-concept explores the following questions:

1) What if we didn't need to parse JSON from the server?
2) What if the server could simply respond with a pre-populated database instead?
3) What might apples-to-apples code look like comparing JSON and SQLite as data transfer formats? Is one way easier
   to reason about and work with than the other?
4) Could SQLite as a data transfer format be worth pursuing in production?   

Years ago, I recall seeing the suggestion of
[using SQLite as an application file format](http://sqlite.org/appfileformat.html). Similarly, the SQLite page
also describes [using SQLite as a data transfer format](https://www.sqlite.org/whentouse.html#wireproto) but does
not provide benchmarks or examples.

I came up empty when searching on my own for concrete examples of SQLite-over-the-wire. So, I decided to write
my own proof-of-concept. If you've also searched for something similar, welcome. :wave: Hopefully this repository
either satisfies your curiosity, or gives you some ideas upon which to build.

**NOTE**: I only compare SQLite and JSON here, but [Protocol Buffers](https://developers.google.com/protocol-buffers/) should
also be in the conversation.

The meat of this PoC is found in [main.swift](./swift-client/SQLiteWireClientDemo/main.swift) for the client, and
[books_controller.rb](./rails-server/app/controllers/api/v1/books_controller.rb) for the server.

## Advantages

 * The API schema can be introspected; Table metadata is self-contained.
 * Data can be easily copied from the server response using simple SQL.
 * JSON is typically an intermediate format, requiring parsing to get to the final state. A SQLite database can _be_ the
   final state; No parsing required.  
 * Ubiquitous data format with fast C libraries pre-installed on target systems.
 * Human-readable via a wide variety of tools. I use the `sqlite3` command line utility.  
 * Trivial BLOB storage (vs. JSON Base64)
 * Built-in enforcement of data types and relationships. 

## Disadvantages

 * JSON parsers can work with streaming responses; SQLite cannot.
 * JSON does not require separate tooling to inspect the data over the wire.

## Benchmarks

The following crude benchmarks illustrate timing. Take these benchmarks with a grain of salt; they were run 
on x86_64 hardware with the client and server code on the same machine. A better round-trip benchmark would
reflect real-world architecture, with the rails server running on x86_64 linux and the swift client running
on an iOS device.

The processing time columns isolate client-side processing effort, while the total time includes the time for the
server to respond with the data and transfer it to the client.

### JSON:API

Payload size: 7398 bytes

| processing time (s) | total time (s) |
| :-- | :-- |
| 0.00460965 | 0.064239692 |
| 0.00141816 | 0.041931752 |
| 0.002465876 | 0.04876441 |
| 0.001436802 | 0.052363299 |
| 0.001436859 | 0.045717272 |
| 0.001648142 | 0.051984467 |
| 0.001378802 | 0.044270852 |
| 0.001409311 | 0.049175685 |
| 0.001312833 | 0.053447003 |
| 0.001372299 | 0.042950414 |

| average processing time (s) | average total time (s) |
| :-- | :-- |
| **0.0018488734** | **0.0494844846** | 

### SQLite

Payload size: 36864 bytes

| processing time (s) | total time (s) |
| :-- | :-- |
| 0.002361436 | 0.057507482 |
| 0.001713821 | 0.048974578 |
| 0.001391009 | 0.048561123 |
| 0.001422691 | 0.048593496 |
| 0.001317175 | 0.045717265 |
| 0.001611825 | 0.050984861 |
| 0.001350341 | 0.053839596 |
| 0.001406202 | 0.049341515 |
| 0.001244471 | 0.049491502 |
| 0.001493613 | 0.046033818 |

| average processing time (s) | average total time (s) |
| :-- | :-- |
| **0.0015312584** | **0.0499045236** |

## Where to go from here?

1) Benchmark with more accurate hardware and include memory consumption.
2) Create a similar Kotlin Android client to benchmark on Android hardware.
3) Explore using in-memory database on both client and server to avoid disk I/O.   
4) Experiment with various payload sizes. What are the edges that make JSON or SQLite the preferred choice?
5) Benchmark against [Protocol Buffers](https://developers.google.com/protocol-buffers/).
6) Make both the client and server code production-worthy (extract libraries if applicable).
