import Foundation
import Observation

@MainActor
@Observable
final class EventsStore {
    private(set) var events: [Event] = []
    private(set) var isLoading = false
    private(set) var loadError: String?

    static let lastSelectedKey = "photoboot.lastSelectedEventId"

    var lastSelectedEvent: Event? {
        guard
            let raw = UserDefaults.standard.string(forKey: Self.lastSelectedKey),
            let id = UUID(uuidString: raw)
        else { return nil }
        return events.first { $0.id == id }
    }

    func rememberSelected(_ event: Event) {
        UserDefaults.standard.set(event.id.uuidString, forKey: Self.lastSelectedKey)
    }

    static func clearRemembered() {
        UserDefaults.standard.removeObject(forKey: lastSelectedKey)
    }

    func load() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }

        do {
            let result: [Event] = try await SupabaseService.shared.client
                .from("events")
                .select(Event.selectColumns)
                .order("created_at", ascending: false)
                .execute()
                .value
            events = result
        } catch {
            loadError = error.localizedDescription
        }
    }

    /// Force-fetches a single event by id, bypassing any in-memory list.
    /// Used by Settings' refresh-event action when the operator wants the
    /// latest row (e.g. after re-uploading templates on the admin side).
    static func refetch(id: UUID) async throws -> Event? {
        let events: [Event] = try await SupabaseService.shared.client
            .from("events")
            .select(Event.selectColumns)
            .eq("id", value: id)
            .limit(1)
            .execute()
            .value
        return events.first
    }

    /// Resolves the persisted "last selected" event by fetching it directly from
    /// Supabase. Returns nil if there's no stored id, the row no longer exists,
    /// or the request fails.
    static func resolveLastSelected() async -> Event? {
        guard
            let raw = UserDefaults.standard.string(forKey: lastSelectedKey),
            let id = UUID(uuidString: raw)
        else { return nil }

        do {
            let events: [Event] = try await SupabaseService.shared.client
                .from("events")
                .select(Event.selectColumns)
                .eq("id", value: id)
                .limit(1)
                .execute()
                .value
            let event = events.first
            if event == nil { clearRemembered() }
            return event
        } catch {
            return nil
        }
    }
}
