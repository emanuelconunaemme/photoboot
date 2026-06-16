import Foundation

struct Strip: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let eventId: UUID
    let composite2x6Path: String?
    let composite4x6Path: String?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case eventId = "event_id"
        case composite2x6Path = "composite_2x6_path"
        case composite4x6Path = "composite_4x6_path"
        case createdAt = "created_at"
    }

    func compositePath(for format: StripFormat) -> String? {
        switch format {
        case .twoBySix: composite2x6Path
        case .fourBySix: composite4x6Path
        }
    }

    var hasAnyComposite: Bool {
        composite2x6Path != nil || composite4x6Path != nil
    }

    static let selectColumns = "id, event_id, composite_2x6_path, composite_4x6_path, created_at"
}
