import Foundation

struct Event: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let name: String
    let slug: String
    let status: String
    let description: String?
    let eventDate: String?           // "YYYY-MM-DD" — Postgres date as ISO string
    let primaryColor: String         // "#RRGGBB"
    let secondaryColor: String       // "#RRGGBB"
    let backgroundPath2x6: String?
    let backgroundPath4x6: String?
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case slug
        case status
        case description
        case eventDate = "event_date"
        case primaryColor = "primary_color"
        case secondaryColor = "secondary_color"
        case backgroundPath2x6 = "background_2x6_path"
        case backgroundPath4x6 = "background_4x6_path"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    func backgroundPath(for format: StripFormat) -> String? {
        switch format {
        case .twoBySix: backgroundPath2x6
        case .fourBySix: backgroundPath4x6
        }
    }

    static let selectColumns =
        "id, name, slug, status, description, event_date, primary_color, secondary_color, background_2x6_path, background_4x6_path, created_at, updated_at"
}

enum StripFormat: String, CaseIterable, Codable, Sendable, Identifiable {
    case twoBySix = "2x6"
    case fourBySix = "4x6"

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .twoBySix: "2×6 strip"
        case .fourBySix: "4×6 print"
        }
    }
}
