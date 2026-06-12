import Foundation
import Observation

@MainActor
@Observable
final class GalleryStore {
    private(set) var strips: [Strip] = []
    private(set) var isLoading = false
    private(set) var loadError: String?

    func load(for event: Event) async {
        if strips.isEmpty { isLoading = true }
        loadError = nil
        defer { isLoading = false }
        do {
            strips = try await StripService.shared.fetchStrips(for: event)
        } catch {
            loadError = error.localizedDescription
        }
    }

    func remove(_ strip: Strip) {
        strips.removeAll { $0.id == strip.id }
    }
}
