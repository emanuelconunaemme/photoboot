import Foundation

struct Strip: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let eventId: UUID
    let compositePath: String?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case eventId = "event_id"
        case compositePath = "composite_path"
        case createdAt = "created_at"
    }

    static let selectColumns = "id, event_id, composite_path, created_at"
}
