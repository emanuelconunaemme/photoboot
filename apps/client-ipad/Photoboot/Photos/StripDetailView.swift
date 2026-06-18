import SwiftUI
import UIKit

struct StripDetailView: View {
    let strip: Strip
    let initialImageData: Data?
    let onDelete: (Strip) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var settings = SettingsStore.shared

    @State private var image: UIImage?
    @State private var imageLoadError: String?
    @State private var deliverySheet: StripService.DeliveryChannel?
    @State private var showDeleteConfirm = false
    @State private var statusMessage: String?
    @State private var isPerforming = false

    init(
        strip: Strip,
        initialImageData: Data? = nil,
        onDelete: @escaping (Strip) -> Void = { _ in }
    ) {
        self.strip = strip
        self.initialImageData = initialImageData
        self.onDelete = onDelete
    }

    var body: some View {
        VStack(spacing: 0) {
            photoArea
            actionBar
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("Your strip")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadImage() }
        .onChange(of: settings.preferredFormat) { _, _ in
            image = nil
            imageLoadError = nil
            Task { await loadImage() }
        }
        .sheet(item: $deliverySheet) { channel in
            DeliveryComposer(strip: strip, channel: channel) { msg in
                showStatus(msg)
            }
            .presentationDetents([.medium, .large])
        }
        .alert("Delete this strip?", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { Task { await performDelete() } }
        } message: {
            Text("It'll be removed from the gallery. This can't be undone.")
        }
        .overlay(alignment: .top) {
            if let statusMessage {
                StatusToast(message: statusMessage)
                    .padding(.top, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.35), value: statusMessage)
    }

    private var photoArea: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(.rect(cornerRadius: 20))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(Brand.gradient, lineWidth: 3)
                    )
                    .shadow(color: .black.opacity(0.12), radius: 18, y: 8)
            } else if let imageLoadError {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text(imageLoadError)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            } else {
                ProgressView().controlSize(.large).tint(Brand.pink)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var actionBar: some View {
        HStack(spacing: 12) {
            actionButton(title: "Email", icon: "envelope.fill", tint: Brand.pink) {
                deliverySheet = .email
            }
            actionButton(title: "SMS", icon: "message.fill", tint: Brand.orange) {
                deliverySheet = .sms
            }
            actionButton(title: "Print", icon: "printer.fill", tint: Brand.purple) {
                performPrint()
            }
            actionButton(title: "Delete", icon: "trash.fill", tint: Color(.systemGray)) {
                showDeleteConfirm = true
            }
        }
        .padding(20)
        .background(
            Color(.systemBackground)
                .shadow(color: .black.opacity(0.08), radius: 14, y: -6)
                .clipShape(.rect(topLeadingRadius: 28, topTrailingRadius: 28))
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private func actionButton(
        title: String,
        icon: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(tint)
                        .frame(width: 60, height: 60)
                        .shadow(color: tint.opacity(0.4), radius: 8, y: 4)
                    Image(systemName: icon)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.white)
                }
                Text(title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .disabled(isPerforming || image == nil)
        .opacity((isPerforming || image == nil) ? 0.5 : 1)
    }

    // MARK: - Loading

    private func loadImage() async {
        // If we have an instant preview from the capture flow (and it
        // matches the user's current preferred format), use it directly.
        // Otherwise download from storage.
        if image != nil { return }
        if let data = initialImageData, let ui = UIImage(data: data) {
            image = ui
            return
        }
        do {
            let data = try await StripService.shared.downloadImageData(
                for: strip,
                format: settings.preferredFormat
            )
            image = UIImage(data: data)
        } catch {
            imageLoadError = error.localizedDescription
        }
    }

    // MARK: - Actions

    private func performPrint() {
        guard let image else { return }
        let info = UIPrintInfo.printInfo()
        info.outputType = .photo
        info.jobName = "Photoboot \(settings.preferredFormat.rawValue) — \(strip.id.uuidString.prefix(8))"

        let controller = UIPrintInteractionController.shared
        controller.printInfo = info
        controller.printingItem = image
        controller.present(animated: true) { _, completed, error in
            Task { @MainActor in
                if let error {
                    showStatus("Print failed: \(error.localizedDescription)")
                } else if completed {
                    showStatus("Sent to printer ✨")
                }
            }
        }
    }

    private func performDelete() async {
        isPerforming = true
        defer { isPerforming = false }
        do {
            try await StripService.shared.delete(strip)
            onDelete(strip)
            dismiss()
        } catch {
            showStatus("Delete failed: \(error.localizedDescription)")
        }
    }

    private func showStatus(_ message: String) {
        statusMessage = message
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            if statusMessage == message {
                statusMessage = nil
            }
        }
    }
}

struct StatusToast: View {
    let message: String
    var body: some View {
        Text(message)
            .font(.callout.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(
                Capsule().fill(Brand.gradient)
                    .shadow(color: .black.opacity(0.15), radius: 8, y: 3)
            )
    }
}
