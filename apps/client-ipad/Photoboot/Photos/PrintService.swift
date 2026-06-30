import Foundation
import Network
import Observation
import UIKit
import os

/// LAN-discovered print server client. Browses Bonjour for
/// `_photoboot-print._tcp`, polls `/health` on a slow timer, and exposes a
/// single async `submit` that POSTs a strip JPEG.
///
/// Server reachability and printer readiness are tracked independently so
/// the Settings screen can show "server is up, printer is out of paper"
/// instead of conflating the two into a single "offline" state. The Print
/// button itself isn't gated by either — it's gated only by the user's
/// `printingEnabled` setting; submit() handles the failure modes.
@MainActor
@Observable
final class PrintService {
    static let shared = PrintService()

    /// Can we reach the LAN print server at all? Independent from whether
    /// the printer itself is ready to take a job. Driven by the combined
    /// signal of Bonjour discovery + last health probe outcome.
    enum ServerState: Equatable {
        case searching
        case reachable(host: String, port: Int)
        case unreachable(reason: String)

        var isReachable: Bool {
            if case .reachable = self { return true }
            return false
        }
    }

    /// Can the printer take a job right now? Reported by /health based on
    /// CUPS's `printer-state-reasons` and accepting-jobs flag.
    enum PrinterState: Equatable {
        case unknown
        case ready
        case notReady(reason: String)

        var isReady: Bool {
            if case .ready = self { return true }
            return false
        }
    }

    enum SubmitError: Error, LocalizedError {
        case serverUnreachable(reason: String)
        case encodeFailed
        case printerNotReady(reason: String)
        case http(status: Int, body: String)
        case transport(Error)

        var errorDescription: String? {
            switch self {
            case .serverUnreachable(let r): return "Print server unreachable: \(r)"
            case .encodeFailed:             return "Couldn't encode the strip for upload."
            case .printerNotReady(let r):   return r
            case .http(let s, let b):       return "Server returned \(s): \(b)"
            case .transport(let e):         return e.localizedDescription
            }
        }
    }

    struct JobReceipt: Decodable {
        let job_id: Int
        let queue: String
    }

    private(set) var serverState: ServerState = .searching
    private(set) var printerState: PrinterState = .unknown
    private(set) var lastHealthAt: Date?

    /// Endpoint we last discovered via Bonjour. Persists across transient
    /// network failures so /health and submit can keep retrying without
    /// waiting for the browser to re-announce the service.
    private var endpoint: (host: String, port: Int)?

    private let log = Logger(subsystem: "com.mazzillie.photoboot", category: "print-service")
    private var browser: NWBrowser?
    private var healthTask: Task<Void, Never>?
    private let serviceType = "_photoboot-print._tcp"
    private let urlSession: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 8
        cfg.timeoutIntervalForResource = 30
        cfg.waitsForConnectivity = false
        return URLSession(configuration: cfg)
    }()

    private init() {}

    // MARK: - Lifecycle

    func start() {
        guard browser == nil else { return }
        log.info("starting Bonjour browser for \(self.serviceType, privacy: .public)")
        let params = NWParameters.tcp
        params.includePeerToPeer = false
        let descriptor = NWBrowser.Descriptor.bonjourWithTXTRecord(type: serviceType, domain: nil)
        let b = NWBrowser(for: descriptor, using: params)
        b.stateUpdateHandler = { [weak self] s in
            Task { @MainActor in
                guard let self else { return }
                switch s {
                case .failed(let err):
                    self.log.error("browser failed: \(err.localizedDescription, privacy: .public)")
                    self.serverState = .unreachable(reason: "Discovery failed: \(err.localizedDescription)")
                    self.printerState = .unknown
                    self.restartAfterDelay()
                case .cancelled:
                    self.log.info("browser cancelled")
                default:
                    break
                }
            }
        }
        b.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor in
                self?.handle(results: results)
            }
        }
        browser = b
        b.start(queue: .main)

        // Health loop. Each tick is a no-op when we have no endpoint yet.
        healthTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.tickHealth()
                try? await Task.sleep(for: .seconds(10))
            }
        }
    }

    func stop() {
        browser?.cancel()
        browser = nil
        healthTask?.cancel()
        healthTask = nil
        serverState = .searching
        printerState = .unknown
        endpoint = nil
    }

    private func restartAfterDelay() {
        browser?.cancel()
        browser = nil
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            start()
        }
    }

    // MARK: - Discovery

    private func handle(results: Set<NWBrowser.Result>) {
        guard let first = results.first else {
            // Empty results — Bonjour no longer sees the service. Don't
            // clear the stored endpoint though; if the server is still
            // alive at the same address, the next health probe will
            // succeed and flip serverState back to reachable.
            if case .reachable = serverState {
                serverState = .unreachable(reason: "Server no longer announced on the network")
                printerState = .unknown
            }
            return
        }
        if case let .service(name, _, _, _) = first.endpoint {
            let host = derivedHostname(fromInstance: name)
            self.endpoint = (host: host, port: 8787)
            serverState = .reachable(host: host, port: 8787)
            log.info("discovered server host=\(host, privacy: .public)")
            // Probe health right away so printerState reflects reality
            // within milliseconds, not 10 seconds.
            Task { @MainActor in await tickHealth() }
        }
    }

    /// Pull the hostname out of an instance name like
    /// "Photoboot Print Server on emanuel-server-0". Falls back to the
    /// full instance name appended with ".local".
    private func derivedHostname(fromInstance instance: String) -> String {
        if let range = instance.range(of: " on ") {
            let host = String(instance[range.upperBound...]).trimmingCharacters(in: .whitespaces)
            return host.hasSuffix(".local") ? host : "\(host).local"
        }
        return instance.hasSuffix(".local") ? instance : "\(instance).local"
    }

    // MARK: - Health

    private struct HealthBody: Decodable {
        let ok: Bool
        let summary: String?
    }

    private func tickHealth() async {
        guard let endpoint else { return }
        var req = URLRequest(url: URL(string: "http://\(endpoint.host):\(endpoint.port)/health")!)
        req.timeoutInterval = 4
        // URLCache could otherwise lock in a stale response across restarts.
        req.cachePolicy = .reloadIgnoringLocalCacheData
        do {
            let (data, response) = try await urlSession.data(for: req)
            guard let http = response as? HTTPURLResponse else { return }
            let body = try? JSONDecoder().decode(HealthBody.self, from: data)
            let summary = body?.summary.flatMap { $0.isEmpty ? nil : $0 }

            // We got an HTTP response, so the server itself is up and
            // reachable. The body says whether the printer is ready.
            serverState = .reachable(host: endpoint.host, port: endpoint.port)
            lastHealthAt = Date()

            if http.statusCode >= 500 {
                // 5xx → service is up but degraded (CUPS unreachable etc.).
                printerState = .notReady(reason: summary ?? "Print service error \(http.statusCode)")
            } else if let body {
                printerState = body.ok ? .ready : .notReady(reason: summary ?? "Printer not ready")
            } else {
                printerState = .notReady(reason: "Couldn't parse server response")
            }
        } catch {
            log.warning("health probe failed: \(error.localizedDescription, privacy: .public)")
            // Network-level failure: the iPad can't talk to the server.
            // Endpoint is preserved so next tick (10s) retries.
            serverState = .unreachable(reason: error.localizedDescription)
            printerState = .unknown
        }
    }

    // MARK: - Print

    func submit(image: UIImage, format: StripFormat, copies: Int = 1) async throws -> JobReceipt {
        // Try whatever endpoint we last discovered, even if the most
        // recent state is .unreachable — the network may have recovered
        // since the last health probe. If we never discovered anything,
        // there's nothing to attempt.
        guard let endpoint else {
            let reason: String
            switch serverState {
            case .searching:            reason = "Still discovering the print server."
            case .unreachable(let r):   reason = r
            case .reachable:            reason = "Unknown"
            }
            throw SubmitError.serverUnreachable(reason: reason)
        }
        guard let jpeg = image.jpegData(compressionQuality: 0.92) else { throw SubmitError.encodeFailed }

        let url = URL(string: "http://\(endpoint.host):\(endpoint.port)/print")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        let boundary = "Boundary-\(UUID().uuidString)"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.httpBody = multipartBody(
            boundary: boundary,
            fields: ["format": format.rawValue, "copies": String(copies)],
            file: (name: "image", filename: "strip.jpg", mime: "image/jpeg", data: jpeg)
        )

        do {
            let (data, response) = try await urlSession.upload(for: req, from: req.httpBody!)
            guard let http = response as? HTTPURLResponse else { throw SubmitError.http(status: 0, body: "") }
            // Successful contact with the server, whatever the status:
            // refresh serverState in case we were stuck on .unreachable.
            serverState = .reachable(host: endpoint.host, port: endpoint.port)
            if !(200..<300).contains(http.statusCode) {
                // Server's pre-flight failed: friendly reason is in detail.summary
                // (FastAPI HTTPException envelope). Surface it directly.
                if let friendly = extractFriendlyError(from: data) {
                    if http.statusCode == 503 {
                        // 503 with a printer reason → reflect it in
                        // printerState so Settings updates immediately,
                        // not on the next 10s tick.
                        printerState = .notReady(reason: friendly)
                    }
                    throw SubmitError.printerNotReady(reason: friendly)
                }
                throw SubmitError.http(status: http.statusCode, body: String(data: data, encoding: .utf8) ?? "")
            }
            return try JSONDecoder().decode(JobReceipt.self, from: data)
        } catch let e as SubmitError {
            throw e
        } catch let e as URLError {
            // Network failure during submit — flip serverState so the
            // user sees the same diagnosis in Settings as they got in
            // the toast. Endpoint is preserved for retries.
            serverState = .unreachable(reason: e.localizedDescription)
            printerState = .unknown
            throw SubmitError.transport(e)
        } catch {
            throw SubmitError.transport(error)
        }
    }

    /// Pull the human-readable summary out of a FastAPI error envelope so the
    /// status toast on the iPad reads "Out of paper" instead of a JSON blob.
    private func extractFriendlyError(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let detail = json["detail"] as? [String: Any], let summary = detail["summary"] as? String, !summary.isEmpty {
            return summary
        }
        if let detail = json["detail"] as? String, !detail.isEmpty {
            return detail
        }
        return nil
    }

    private func multipartBody(
        boundary: String,
        fields: [String: String],
        file: (name: String, filename: String, mime: String, data: Data)
    ) -> Data {
        var body = Data()
        let lineBreak = "\r\n"
        for (key, value) in fields {
            body.append("--\(boundary)\(lineBreak)".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(key)\"\(lineBreak)\(lineBreak)".data(using: .utf8)!)
            body.append("\(value)\(lineBreak)".data(using: .utf8)!)
        }
        body.append("--\(boundary)\(lineBreak)".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"\(file.name)\"; filename=\"\(file.filename)\"\(lineBreak)".data(using: .utf8)!)
        body.append("Content-Type: \(file.mime)\(lineBreak)\(lineBreak)".data(using: .utf8)!)
        body.append(file.data)
        body.append("\(lineBreak)--\(boundary)--\(lineBreak)".data(using: .utf8)!)
        return body
    }
}
