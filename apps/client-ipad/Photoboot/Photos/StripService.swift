import Foundation
import Supabase
import os

@MainActor
final class StripService {
    static let shared = StripService()
    private let log = Logger(subsystem: "com.mazzillie.photoboot", category: "strip-service")
    private init() {}

    func fetchStrips(for event: Event) async throws -> [Strip] {
        let client = SupabaseService.shared.client
        let strips: [Strip] = try await client
            .from("strips")
            .select(Strip.selectColumns)
            .eq("event_id", value: event.id)
            .order("created_at", ascending: false)
            .execute()
            .value
        return strips.filter { $0.hasAnyComposite }
    }

    func signedURL(for strip: Strip, format: StripFormat, expiresIn seconds: Int = 3600) async throws -> URL {
        guard let path = strip.compositePath(for: format) else {
            throw StripServiceError.missingCompositePath
        }
        return try await SupabaseService.shared.client.storage
            .from("composites")
            .createSignedURL(path: path, expiresIn: seconds)
    }

    func downloadImageData(for strip: Strip, format: StripFormat) async throws -> Data {
        let url = try await signedURL(for: strip, format: format)
        let (data, response) = try await URLSession.shared.data(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw StripServiceError.downloadFailed(http.statusCode)
        }
        return data
    }

    func delete(_ strip: Strip) async throws {
        let client = SupabaseService.shared.client
        var paths: [String] = []
        if let p = strip.composite2x6Path { paths.append(p) }
        if let p = strip.composite4x6Path { paths.append(p) }
        if !paths.isEmpty {
            _ = try? await client.storage.from("composites").remove(paths: paths)
        }
        try await client.from("strips").delete().eq("id", value: strip.id).execute()
        log.info("deleted strip \(strip.id.uuidString)")
    }

    func createDelivery(
        strip: Strip,
        channel: DeliveryChannel,
        recipient: String
    ) async throws {
        struct NewDelivery: Encodable {
            let strip_id: UUID
            let channel: String
            let recipient: String
        }
        try await SupabaseService.shared.client
            .from("deliveries")
            .insert(NewDelivery(strip_id: strip.id, channel: channel.rawValue, recipient: recipient))
            .execute()
        log.info("queued \(channel.rawValue) for strip \(strip.id.uuidString)")
    }

    enum DeliveryChannel: String, Identifiable, CaseIterable {
        case email, sms
        var id: String { rawValue }
        var displayTitle: String { self == .email ? "Send via email" : "Send via SMS" }
        var systemImage: String { self == .email ? "envelope.fill" : "message.fill" }
        var inputPlaceholder: String {
            self == .email ? "name@example.com" : "+1 555 123 4567"
        }
    }

    enum StripServiceError: LocalizedError {
        case missingCompositePath
        case downloadFailed(Int)
        var errorDescription: String? {
            switch self {
            case .missingCompositePath: "Strip has no composite for that format."
            case .downloadFailed(let code): "Image download failed (HTTP \(code))."
            }
        }
    }
}
