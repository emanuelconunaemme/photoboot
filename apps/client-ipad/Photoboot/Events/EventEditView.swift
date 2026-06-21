import SwiftUI
import PhotosUI
import UIKit
import Supabase

/// Mirrors apps/admin-web's EditEventForm: name, description, optional
/// date, two colors, two background images. New images upload to the
/// `templates` bucket and the events row is patched in a single update.
struct EventEditView: View {
    let event: Event
    let onSaved: (Event) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var description: String
    @State private var hasDate: Bool
    @State private var eventDate: Date
    @State private var primaryColor: Color
    @State private var secondaryColor: Color
    @State private var bg2x6Item: PhotosPickerItem?
    @State private var bg4x6Item: PhotosPickerItem?
    @State private var bg2x6NewData: Data?
    @State private var bg4x6NewData: Data?
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(event: Event, onSaved: @escaping (Event) -> Void) {
        self.event = event
        self.onSaved = onSaved
        _name = State(initialValue: event.name)
        _description = State(initialValue: event.description ?? "")
        let parsed = Self.parseDate(event.eventDate)
        _hasDate = State(initialValue: parsed != nil)
        _eventDate = State(initialValue: parsed ?? Date())
        _primaryColor = State(initialValue: Color(hex: event.primaryColor))
        _secondaryColor = State(initialValue: Color(hex: event.secondaryColor))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Event name", text: $name)
                    TextField(
                        "Description (optional)",
                        text: $description,
                        axis: .vertical
                    )
                    .lineLimit(2...4)
                    Toggle("Has event date", isOn: $hasDate)
                    if hasDate {
                        DatePicker(
                            "Event date",
                            selection: $eventDate,
                            displayedComponents: .date
                        )
                    }
                }

                Section("Colors") {
                    ColorPicker("Primary", selection: $primaryColor, supportsOpacity: false)
                    ColorPicker("Secondary", selection: $secondaryColor, supportsOpacity: false)
                }

                Section {
                    BackgroundRow(
                        label: "2×6 strip background",
                        existingPath: event.backgroundPath2x6,
                        version: event.updatedAt,
                        newData: bg2x6NewData,
                        item: $bg2x6Item
                    )
                    BackgroundRow(
                        label: "4×6 print background",
                        existingPath: event.backgroundPath4x6,
                        version: event.updatedAt,
                        newData: bg4x6NewData,
                        item: $bg4x6Item
                    )
                } header: {
                    Text("Backgrounds")
                } footer: {
                    Text("Leave a slot empty to keep the current background.")
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .font(.callout)
                    }
                }
            }
            .navigationTitle("Edit event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : "Save") {
                        Task { await save() }
                    }
                    .disabled(isSaving || name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onChange(of: bg2x6Item) { _, item in
                Task { bg2x6NewData = await loadData(from: item) }
            }
            .onChange(of: bg4x6Item) { _, item in
                Task { bg4x6NewData = await loadData(from: item) }
            }
        }
    }

    // MARK: - Save

    private func save() async {
        errorMessage = nil
        isSaving = true
        defer { isSaving = false }

        let client = SupabaseService.shared.client
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else {
            errorMessage = "Event name required"
            return
        }

        var bg2x6Path: String?
        var bg4x6Path: String?

        if let data = bg2x6NewData {
            do {
                bg2x6Path = try await uploadBackground(data, format: "2x6")
            } catch {
                errorMessage = "Couldn't upload 2×6 background: \(error.localizedDescription)"
                return
            }
        }
        if let data = bg4x6NewData {
            do {
                bg4x6Path = try await uploadBackground(data, format: "4x6")
            } catch {
                errorMessage = "Couldn't upload 4×6 background: \(error.localizedDescription)"
                return
            }
        }

        let trimmedDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
        let patch = EventUpdate(
            name: trimmedName,
            description: trimmedDescription.isEmpty ? nil : trimmedDescription,
            event_date: hasDate ? Self.formatDate(eventDate) : nil,
            primary_color: primaryColor.hexString,
            secondary_color: secondaryColor.hexString,
            background_2x6_path: bg2x6Path,
            background_4x6_path: bg4x6Path
        )

        do {
            let updated: Event = try await client
                .from("events")
                .update(patch)
                .eq("id", value: event.id)
                .select(Event.selectColumns)
                .single()
                .execute()
                .value
            await BackgroundCache.shared.preload(for: updated)
            onSaved(updated)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func uploadBackground(_ rawData: Data, format: String) async throws -> String {
        // Re-encode to JPEG so the storage path extension is predictable
        // regardless of source format (HEIC, PNG, JPEG, …).
        guard let image = UIImage(data: rawData),
              let jpeg = image.jpegData(compressionQuality: 0.92)
        else {
            throw EditError.invalidImage
        }
        let path = "\(event.id.uuidString.lowercased())/bg-\(format).jpg"
        _ = try await SupabaseService.shared.client.storage
            .from("templates")
            .upload(
                path,
                data: jpeg,
                options: FileOptions(contentType: "image/jpeg", upsert: true)
            )
        return path
    }

    private func loadData(from item: PhotosPickerItem?) async -> Data? {
        guard let item else { return nil }
        return try? await item.loadTransferable(type: Data.self)
    }

    // MARK: - Date helpers

    private static func parseDate(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        return dateFormatter.date(from: raw)
    }

    private static func formatDate(_ date: Date) -> String {
        dateFormatter.string(from: date)
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .iso8601)
        f.timeZone = TimeZone(identifier: "UTC")
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    // MARK: - Wire types

    /// `encodeIfPresent` for background paths so omitted slots don't
    /// overwrite existing rows with NULL — text fields use `encode` so
    /// clearing the description / date IS persisted.
    private struct EventUpdate: Encodable {
        let name: String
        let description: String?
        let event_date: String?
        let primary_color: String
        let secondary_color: String
        let background_2x6_path: String?
        let background_4x6_path: String?

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: Keys.self)
            try c.encode(name, forKey: .name)
            try c.encode(description, forKey: .description)
            try c.encode(event_date, forKey: .event_date)
            try c.encode(primary_color, forKey: .primary_color)
            try c.encode(secondary_color, forKey: .secondary_color)
            try c.encodeIfPresent(background_2x6_path, forKey: .background_2x6_path)
            try c.encodeIfPresent(background_4x6_path, forKey: .background_4x6_path)
        }

        enum Keys: String, CodingKey {
            case name
            case description
            case event_date
            case primary_color
            case secondary_color
            case background_2x6_path
            case background_4x6_path
        }
    }

    private enum EditError: LocalizedError {
        case invalidImage
        var errorDescription: String? {
            switch self {
            case .invalidImage: "Couldn't read that image."
            }
        }
    }
}

private struct BackgroundRow: View {
    let label: String
    let existingPath: String?
    let version: Date
    let newData: Data?
    @Binding var item: PhotosPickerItem?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                preview
                PhotosPicker(
                    selection: $item,
                    matching: .images,
                    photoLibrary: .shared()
                ) {
                    Label(
                        newData != nil ? "Change" : "Replace",
                        systemImage: "photo"
                    )
                }
                .buttonStyle(.bordered)

                if newData != nil {
                    Button(role: .destructive) {
                        item = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var preview: some View {
        if let newData, let ui = UIImage(data: newData) {
            Image(uiImage: ui)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 80, height: 60)
                .clipShape(.rect(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Brand.pink, lineWidth: 2)
                )
        } else if let existingPath,
                  let url = BackgroundCache.publicURL(
                    path: existingPath,
                    version: version.timeIntervalSince1970
                  ) {
            AsyncImage(url: url) { phase in
                if let img = phase.image {
                    img.resizable().aspectRatio(contentMode: .fill)
                } else {
                    Color.secondary.opacity(0.15)
                }
            }
            .frame(width: 80, height: 60)
            .clipShape(.rect(cornerRadius: 6))
        } else {
            RoundedRectangle(cornerRadius: 6)
                .fill(.secondary.opacity(0.15))
                .frame(width: 80, height: 60)
        }
    }
}
