import Foundation

struct Snippet: Identifiable, Codable {
    let id: UUID
    var name: String
    var value: String
}