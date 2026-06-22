import Foundation
import UIKit
import os

/// One-shot loader for event background images. The templates bucket is
/// public-read, so we construct the URL directly (no signed URL needed) and
/// download via URLSession.
///
/// Two-layer cache: in-memory (UIImage) on top of a disk cache under
/// Caches/photoboot/templates/. Both are keyed on (path, version) where
/// version is event.updated_at — an admin-side edit bumps the version, so
/// next preload re-fetches and prunes the stale on-disk copy.
///
/// Call `preload(for: event)` once per event entry — both formats download
/// (or load from disk) in parallel. `image(for: path)` returns the cached
/// UIImage at render time.
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
    /// given version. Disk-first, then network. Concurrent calls coalesce.
    func load(path: String, version: Date) async {
        let v = version.timeIntervalSince1970
        if versionByPath[path] == v, byPath[path] != nil { return }
        if loading.contains(path) { return }
        loading.insert(path)
        defer { loading.remove(path) }

        // Disk hit — no network round-trip after a cold launch.
        if let data = Self.readFromDisk(path: path, version: v),
           let image = UIImage(data: data) {
            byPath[path] = image
            versionByPath[path] = v
            log.info("loaded bg \(path) from disk (\(data.count) bytes)")
            return
        }

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
                Self.writeToDisk(data: data, path: path, version: v)
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

    // MARK: - Disk cache

    private static func cacheDirectory() -> URL? {
        guard let caches = FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask).first
        else { return nil }
        let dir = caches.appendingPathComponent("photoboot/templates", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Sanitised + version-suffixed filename so a version bump produces a
    /// distinct file we can detect (and prune the old one).
    private static func filename(for path: String, version: TimeInterval) -> String {
        let safe = path
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "?", with: "_")
        let v = Int((version * 1000).rounded())
        return "\(safe)@\(v).bin"
    }

    private static func readFromDisk(path: String, version: TimeInterval) -> Data? {
        guard let dir = cacheDirectory() else { return nil }
        let file = dir.appendingPathComponent(filename(for: path, version: version))
        return try? Data(contentsOf: file)
    }

    private static func writeToDisk(data: Data, path: String, version: TimeInterval) {
        guard let dir = cacheDirectory() else { return }
        let file = dir.appendingPathComponent(filename(for: path, version: version))
        try? data.write(to: file, options: .atomic)
        pruneStale(currentFile: file, path: path, in: dir)
    }

    /// After writing a new version, drop any older files with the same
    /// sanitised path prefix so the cache directory doesn't grow forever.
    private static func pruneStale(currentFile: URL, path: String, in dir: URL) {
        let safe = path
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "?", with: "_")
        let prefix = "\(safe)@"
        let files = (try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: nil
        )) ?? []
        for file in files
        where file.lastPathComponent.hasPrefix(prefix) && file != currentFile {
            try? FileManager.default.removeItem(at: file)
        }
    }
}
