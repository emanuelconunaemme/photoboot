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
    let stripTitle: String?
    let stripSubtitle: String?
    let backgroundPath2x6: String?
    let backgroundPath4x6: String?
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
        case stripTitle = "strip_title"
        case stripSubtitle = "strip_subtitle"
        case backgroundPath2x6 = "background_2x6_path"
        case backgroundPath4x6 = "background_4x6_path"
        case createdAt = "created_at"
    }

    /// Effective title used on the strip composite — falls back to event name.
    var effectiveStripTitle: String {
        let s = (stripTitle ?? "").trimmingCharacters(in: .whitespaces)
        return s.isEmpty ? name : s
    }

    /// Effective subtitle — falls back to formatted event date if no explicit subtitle.
    var effectiveStripSubtitle: String? {
        let s = (stripSubtitle ?? "").trimmingCharacters(in: .whitespaces)
        if !s.isEmpty { return s }
        return formattedEventDate
    }

    private var formattedEventDate: String? {
        guard let eventDate else { return nil }
        let parser = DateFormatter()
        parser.calendar = Calendar(identifier: .iso8601)
        parser.timeZone = TimeZone(identifier: "UTC")
        parser.dateFormat = "yyyy-MM-dd"
        guard let date = parser.date(from: eventDate) else { return nil }
        let display = DateFormatter()
        display.dateStyle = .long
        return display.string(from: date)
    }

    func backgroundPath(for format: StripFormat) -> String? {
        switch format {
        case .twoBySix: backgroundPath2x6
        case .fourBySix: backgroundPath4x6
        }
    }

    static let selectColumns =
        "id, name, slug, status, description, event_date, primary_color, secondary_color, strip_title, strip_subtitle, background_2x6_path, background_4x6_path, created_at"
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
