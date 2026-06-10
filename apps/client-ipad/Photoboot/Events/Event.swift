import Foundation

struct Event: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let name: String
    let slug: String
    let status: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case slug
        case status
        case createdAt = "created_at"
    }
}
