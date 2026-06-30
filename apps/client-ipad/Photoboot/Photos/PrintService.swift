import Foundation
import Network
import Observation
import UIKit
import os

/// LAN-discovered print server. Browses for `_photoboot-print._tcp`, polls
/// the discovered server's `/health` on a slow timer, and exposes a single
/// async `submit` that POSTs a strip JPEG.
///
/// The UI hides the Print button whenever `state` is not `.online`. The
/// settings screen surfaces the raw state for debugging.
@MainActor
@Observable
final class PrintService {
    static let shared = PrintService()

    enum State: Equatable {
        case searching
        case online(host: String, port: Int)
        case offline(reason: String)

        var isOnline: Bool {
            if case .online = self { return true }
            return false
        }
    }

    enum SubmitError: Error, LocalizedError {
        case notOnline
        case encodeFailed
        case http(status: Int, body: String)
        case transport(Error)

        var errorDescription: String? {
            switch self {
            case .notOnline:          return "Print server is offline."
            case .encodeFailed:       return "Couldn't encode the strip for upload."
            case .http(let s, let b): return "Server returned \(s): \(b)"
            case .transport(let e):   return e.localizedDescription
            }
        }
    }

    struct JobReceipt: Decodable {
        let job_id: Int
        let queue: String
    }

    private(set) var state: State = .searching
    private(set) var lastHealthAt: Date?

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
                    self.state = .offline(reason: "Discovery failed: \(err.localizedDescription)")
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

        // Start the health loop. It tolerates "no endpoint yet" by sleeping.
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
        state = .searching
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
        // Pick the first result. Multiple servers on the same LAN is not a
        // scenario we plan for; if it ever happens, prefer the one whose
        // name matches a configured host (not implemented).
        guard let first = results.first else {
            // Stay in .searching for a moment in case a result is about to
            // arrive; if /health is still failing, the timer flips us to
            // .offline next tick.
            if case .online = state { state = .searching }
            return
        }
        // Resolve the endpoint name to a host:port. NWBrowser's endpoint
        // type is .service(name, type, domain, interface); we ask NWConnection
        // to resolve it lazily by handing the .service endpoint to URLSession
        // via a constructed `.local` URL — iOS resolves Bonjour on `.local`
        // hostnames automatically when NSLocalNetworkUsageDescription is set.
        //
        // We extract the instance name (e.g. "Photoboot Print Server on
        // emanuel-server-0") and the TXT-advertised port via NWBrowser metadata.
        if case let .service(name, _, _, _) = first.endpoint {
            // Avahi publishes the host's mDNS name as ".local" — derive it
            // from the instance name's "on <hostname>" suffix our service
            // file uses. Fall back to the instance name verbatim.
            let host = derivedHostname(fromInstance: name)
            // Port is fixed (8787) in our service definition; reading from
            // TXT would require resolving the endpoint, which we skip for
            // simplicity given a known port.
            state = .online(host: host, port: 8787)
            log.info("discovered server host=\(host, privacy: .public)")
            // Probe health immediately so we don't wait up to 10s for the
            // first scheduled tick — if the discovery is stale, this flips
            // us back to .offline right away.
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
        guard case .online(let host, let port) = state else { return }
        var req = URLRequest(url: URL(string: "http://\(host):\(port)/health")!)
        req.timeoutInterval = 4
        // The server caches its own headers but URLSession's URLCache may
        // hold an older response. Always go to the network for health.
        req.cachePolicy = .reloadIgnoringLocalCacheData
        do {
            let (data, response) = try await urlSession.data(for: req)
            guard let http = response as? HTTPURLResponse else { return }
            // 5xx means the print *service* itself is down (e.g. can't
            // reach CUPS). Treat as offline with the server's reason.
            if http.statusCode >= 500 {
                let body = try? JSONDecoder().decode(HealthBody.self, from: data)
                state = .offline(reason: body?.summary.flatMap { $0.isEmpty ? nil : $0 } ?? "Print service error \(http.statusCode)")
                return
            }
            guard let body = try? JSONDecoder().decode(HealthBody.self, from: data) else {
                state = .offline(reason: "Couldn't parse server response")
                return
            }
            if body.ok {
                lastHealthAt = Date()
                state = .online(host: host, port: port)
            } else {
                // Printer not ready — surface the server's specific
                // reason ("Out of paper", "Printer cover open", …).
                state = .offline(reason: body.summary.flatMap { $0.isEmpty ? nil : $0 } ?? "Printer not ready")
            }
        } catch {
            log.warning("health probe failed: \(error.localizedDescription, privacy: .public)")
            state = .offline(reason: error.localizedDescription)
            restartAfterDelay()
        }
    }

    // MARK: - Print

    func submit(image: UIImage, format: StripFormat, copies: Int = 1) async throws -> JobReceipt {
        guard case .online(let host, let port) = state else { throw SubmitError.notOnline }
        guard let jpeg = image.jpegData(compressionQuality: 0.92) else { throw SubmitError.encodeFailed }

        let url = URL(string: "http://\(host):\(port)/print")!
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
            if !(200..<300).contains(http.statusCode) {
                // FastAPI's HTTPException returns {"detail": ...} where detail
                // can be a string OR our structured object with a summary.
                let body = extractFriendlyError(from: data) ?? (String(data: data, encoding: .utf8) ?? "")
                throw SubmitError.http(status: http.statusCode, body: body)
            }
            return try JSONDecoder().decode(JobReceipt.self, from: data)
        } catch let e as SubmitError {
            throw e
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
