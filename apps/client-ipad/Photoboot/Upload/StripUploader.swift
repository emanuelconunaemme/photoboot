import Foundation
import UIKit
import Supabase
import os

@MainActor
struct StripUploader {
    private let log = Logger(subsystem: "com.mazzillie.photoboot", category: "upload")

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

        log.info("rendering strip composite")
        guard let compositeData = StripRenderer.render(event: event, photos: images) else {
            throw UploadError.renderFailed
        }

        let stripInserted: InsertedId = try await client
            .from("strips")
            .insert(NewStripInsert(event_id: event.id))
            .select("id")
            .single()
            .execute()
            .value

        let compositePath = "\(event.id.uuidString.lowercased())/\(stripInserted.id.uuidString.lowercased()).jpg"
        _ = try await client.storage
            .from("composites")
            .upload(
                compositePath,
                data: compositeData,
                options: FileOptions(contentType: "image/jpeg")
            )
        log.info("uploaded composite (\(compositeData.count) bytes) to composites/\(compositePath)")

        let strip: Strip = try await client
            .from("strips")
            .update(StripCompositeUpdate(composite_path: compositePath))
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
            case .renderFailed: "Couldn't render the strip composite."
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
    private struct StripCompositeUpdate: Encodable {
        let composite_path: String
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
