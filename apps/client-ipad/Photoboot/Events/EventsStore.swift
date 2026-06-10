import Foundation
import Observation

@MainActor
@Observable
final class EventsStore {
    private(set) var events: [Event] = []
    private(set) var isLoading = false
    private(set) var loadError: String?

    private let lastSelectedKey = "photoboot.lastSelectedEventId"

    var lastSelectedEvent: Event? {
        guard
            let raw = UserDefaults.standard.string(forKey: lastSelectedKey),
            let id = UUID(uuidString: raw)
        else { return nil }
        return events.first { $0.id == id }
    }

    func rememberSelected(_ event: Event) {
        UserDefaults.standard.set(event.id.uuidString, forKey: lastSelectedKey)
    }

    func load() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }

        do {
            let result: [Event] = try await SupabaseService.shared.client
                .from("events")
                .select("id, name, slug, status, created_at")
                .order("created_at", ascending: false)
                .execute()
                .value
            events = result
        } catch {
            loadError = error.localizedDescription
        }
    }
}
