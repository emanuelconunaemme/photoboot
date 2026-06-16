import Foundation
import UIKit
import os

/// One-shot loader for event background images. The templates bucket is
/// public-read, so we construct the URL directly (no signed URL needed) and
/// download via URLSession.
///
/// Cache is path-keyed with a tracked version (event.updatedAt) so an
/// edit on the web admin invalidates the local copy on next preload.
///
/// Call `preload(for: event)` once when the current event is resolved —
/// both formats download in parallel. `image(for: path)` returns the
/// cached UIImage at render time (capture flow shouldn't re-fetch).
@MainActor
@Observable
final class BackgroundCache {
    static let shared = BackgroundCache()
    private init() {}

    private let log = Logger(subsystem: "com.mazzillie.photoboot", category: "bg-cache")
    private var byPath: [String: UIImage] = [:]
    private var versionByPath: [String: TimeInterval] = [:]
    private var loading: Set<String> = []

    func image(for path: String?) -> UIImage? {
        guard let path else { return nil }
        return byPath[path]
    }

    /// Loads the background image at `path` if not already cached at the
    /// given version. Concurrent calls coalesce.
    func load(path: String, version: Date) async {
        let v = version.timeIntervalSince1970
        if versionByPath[path] == v, byPath[path] != nil { return }
        if loading.contains(path) { return }
        loading.insert(path)
        defer { loading.remove(path) }

        guard let url = Self.publicURL(path: path, version: v) else { return }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                log.error("bg \(path) HTTP \(http.statusCode)")
                return
            }
            if let image = UIImage(data: data) {
                byPath[path] = image
                versionByPath[path] = v
                log.info("cached bg \(path) v=\(v) (\(data.count) bytes)")
            }
        } catch {
            log.error("bg \(path) fetch failed: \(String(describing: error))")
        }
    }

    /// Pre-fetches both formats' backgrounds for an event in parallel.
    func preload(for event: Event) async {
        await withTaskGroup(of: Void.self) { group in
            if let path = event.backgroundPath2x6 {
                group.addTask { await self.load(path: path, version: event.updatedAt) }
            }
            if let path = event.backgroundPath4x6 {
                group.addTask { await self.load(path: path, version: event.updatedAt) }
            }
        }
    }

    /// Public templates URL with a `v=` cache-buster so any intermediate
    /// caches (URLSession, CDN) serve fresh content after an edit.
    static func publicURL(path: String, version: TimeInterval) -> URL? {
        let base = AppConfig.supabaseURL.absoluteString
        return URL(string: "\(base)/storage/v1/object/public/templates/\(path)?v=\(version)")
    }
}
