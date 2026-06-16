import Foundation
import UIKit
import os

/// One-shot loader for event background images. The templates bucket is
/// public-read, so we construct the URL directly (no signed URL needed) and
/// download via URLSession.
///
/// Call `preload(for: event)` once when the current event is resolved — both
/// formats download in parallel. `image(for: path)` returns the cached UIImage
/// at render time (capture flow shouldn't re-fetch backgrounds).
@MainActor
@Observable
final class BackgroundCache {
    static let shared = BackgroundCache()
    private init() {}

    private let log = Logger(subsystem: "com.mazzillie.photoboot", category: "bg-cache")
    private var byPath: [String: UIImage] = [:]
    private var loading: Set<String> = []

    func image(for path: String?) -> UIImage? {
        guard let path else { return nil }
        return byPath[path]
    }

    /// Loads the background image at `path` if not already cached or loading.
    /// Concurrent calls for the same path coalesce.
    func load(path: String) async {
        if byPath[path] != nil || loading.contains(path) { return }
        loading.insert(path)
        defer { loading.remove(path) }

        guard let url = Self.publicURL(path: path) else { return }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                log.error("bg \(path) HTTP \(http.statusCode)")
                return
            }
            if let image = UIImage(data: data) {
                byPath[path] = image
                log.info("cached bg \(path) (\(data.count) bytes)")
            }
        } catch {
            log.error("bg \(path) fetch failed: \(String(describing: error))")
        }
    }

    /// Pre-fetches both formats' backgrounds for an event in parallel.
    func preload(for event: Event) async {
        await withTaskGroup(of: Void.self) { group in
            if let path = event.backgroundPath2x6 {
                group.addTask { await self.load(path: path) }
            }
            if let path = event.backgroundPath4x6 {
                group.addTask { await self.load(path: path) }
            }
        }
    }

    static func publicURL(path: String) -> URL? {
        URL(
            string: "\(AppConfig.supabaseURL.absoluteString)/storage/v1/object/public/templates/\(path)"
        )
    }
}
