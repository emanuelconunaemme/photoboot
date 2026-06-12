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
    let shotsPerStrip: Int
    let inviteImagePath: String?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case slug
        case status
        case description
        case eventDate = "event_date"
        case primaryColor = "primary_color"
        case secondaryColor = "secondary_color"
        case shotsPerStrip = "shots_per_strip"
        case inviteImagePath = "invite_image_path"
        case createdAt = "created_at"
    }

    /// Postgres `date` columns come back as "YYYY-MM-DD" strings — convert when
    /// needed for display.
    var eventDateValue: Date? {
        guard let eventDate else { return nil }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: eventDate)
    }

    static let selectColumns =
        "id, name, slug, status, description, event_date, primary_color, secondary_color, shots_per_strip, invite_image_path, created_at"
}
