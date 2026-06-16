import Foundation
import UIKit
import Supabase
import os

@MainActor
struct StripUploader {
    private let log = Logger(subsystem: "com.mazzillie.photoboot", category: "upload")

    /// Uploads the 2 raw photos + both composites + creates the strip row.
    /// Both composite paths are written in a single UPDATE so the
    /// strip-ready trigger fires once (not twice).
    func upload(rawPhotos: [Data], for event: Event) async throws -> Strip {
        let client = SupabaseService.shared.client

        guard (try? await client.auth.session) != nil else {
            log.error("upload aborted — no Supabase session")
            throw UploadError.notAuthenticated
        }

        let images = rawPhotos.compactMap { UIImage(data: $0) }
        guard images.count == rawPhotos.count else {
            throw UploadError.invalidImageData
        }

        log.info("uploading \(rawPhotos.count) raw photo(s) for event \(event.id.uuidString)")
        var photoIds: [UUID] = []
        for (idx, data) in rawPhotos.enumerated() {
            let inserted: InsertedId = try await client
                .from("photos")
                .insert(NewPhotoInsert(
                    event_id: event.id,
                    capture_mode: "strip",
                    status: "uploading"
                ))
                .select("id")
                .single()
                .execute()
                .value

            let path = "\(event.id.uuidString.lowercased())/\(inserted.id.uuidString.lowercased()).jpg"
            _ = try await client.storage
                .from("photos")
                .upload(
                    path,
                    data: data,
                    options: FileOptions(contentType: "image/jpeg")
                )

            try await client
                .from("photos")
                .update(PhotoReadyUpdate(status: "ready", storage_path: path))
                .eq("id", value: inserted.id)
                .execute()

            photoIds.append(inserted.id)
            log.info("photo \(idx + 1)/\(rawPhotos.count) uploaded")
        }

        log.info("rendering both strip composites")
        let (data2x6, data4x6) = StripRenderer.renderBoth(event: event, photos: images)
        guard let data2x6, let data4x6 else {
            throw UploadError.renderFailed
        }

        let stripInserted: InsertedId = try await client
            .from("strips")
            .insert(NewStripInsert(event_id: event.id))
            .select("id")
            .single()
            .execute()
            .value

        let basePath = "\(event.id.uuidString.lowercased())/\(stripInserted.id.uuidString.lowercased())"
        let path2x6 = "\(basePath)-2x6.jpg"
        let path4x6 = "\(basePath)-4x6.jpg"

        _ = try await client.storage
            .from("composites")
            .upload(path2x6, data: data2x6, options: FileOptions(contentType: "image/jpeg"))
        log.info("uploaded 2x6 composite (\(data2x6.count) bytes)")

        _ = try await client.storage
            .from("composites")
            .upload(path4x6, data: data4x6, options: FileOptions(contentType: "image/jpeg"))
        log.info("uploaded 4x6 composite (\(data4x6.count) bytes)")

        // Single update so the strip-ready trigger fires exactly once.
        let strip: Strip = try await client
            .from("strips")
            .update(StripCompositesUpdate(
                composite_2x6_path: path2x6,
                composite_4x6_path: path4x6
            ))
            .eq("id", value: stripInserted.id)
            .select(Strip.selectColumns)
            .single()
            .execute()
            .value

        let stripPhotos = photoIds.enumerated().map { idx, photoId in
            NewStripPhoto(strip_id: strip.id, photo_id: photoId, position: idx + 1)
        }
        try await client.from("strip_photos").insert(stripPhotos).execute()

        log.info("strip \(strip.id.uuidString) complete")
        return strip
    }

    enum UploadError: LocalizedError {
        case notAuthenticated
        case invalidImageData
        case renderFailed
        var errorDescription: String? {
            switch self {
            case .notAuthenticated: "Not signed in. Sign out and back in."
            case .invalidImageData: "Couldn't read captured image data."
            case .renderFailed: "Couldn't render one or both strip composites."
            }
        }
    }

    private struct NewPhotoInsert: Encodable {
        let event_id: UUID
        let capture_mode: String
        let status: String
    }
    private struct PhotoReadyUpdate: Encodable {
        let status: String
        let storage_path: String
    }
    private struct NewStripInsert: Encodable {
        let event_id: UUID
    }
    private struct StripCompositesUpdate: Encodable {
        let composite_2x6_path: String
        let composite_4x6_path: String
    }
    private struct NewStripPhoto: Encodable {
        let strip_id: UUID
        let photo_id: UUID
        let position: Int
    }
    private struct InsertedId: Decodable {
        let id: UUID
    }
}
