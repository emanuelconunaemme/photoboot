import Foundation
import Supabase
import os

@MainActor
struct PhotoUploader {
    private let log = Logger(subsystem: "xyz.saga.photoboot", category: "upload")

    func upload(imageData: Data, for event: Event) async throws {
        let client = SupabaseService.shared.client

        let newPhoto = NewPhotoInsert(
            event_id: event.id,
            capture_mode: "single",
            status: "uploading"
        )

        let inserted: InsertedPhotoId = try await client
            .from("photos")
            .insert(newPhoto)
            .select("id")
            .single()
            .execute()
            .value

        log.info("Inserted photo row id=\(inserted.id.uuidString)")

        let path = "\(event.id.uuidString)/\(inserted.id.uuidString).jpg"

        _ = try await client.storage
            .from("photos")
            .upload(
                path,
                data: imageData,
                options: FileOptions(contentType: "image/jpeg")
            )

        log.info("Uploaded \(imageData.count) bytes to \(path)")

        let update = PhotoReadyUpdate(status: "ready", storage_path: path)
        try await client
            .from("photos")
            .update(update)
            .eq("id", value: inserted.id)
            .execute()
    }

    // MARK: - DTOs

    private struct NewPhotoInsert: Encodable {
        let event_id: UUID
        let capture_mode: String
        let status: String
    }

    private struct InsertedPhotoId: Decodable {
        let id: UUID
    }

    private struct PhotoReadyUpdate: Encodable {
        let status: String
        let storage_path: String
    }
}
