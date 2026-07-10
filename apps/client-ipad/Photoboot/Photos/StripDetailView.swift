import SwiftUI
import UIKit

struct StripDetailView: View {
    let strip: Strip
    let initialImageData: Data?
    /// When true, the view auto-dismisses after the configured idle
    /// timeout to return the kiosk to the camera. Capture flow sets this
    /// to true; gallery browsing leaves it false.
    let autoDismissOnInactivity: Bool
    let onDelete: (Strip) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var settings = SettingsStore.shared

    /// Format currently being previewed / delivered / printed. Seeded
    /// from the Settings default at open time; the toolbar picker lets
    /// the guest flip it per-strip without touching global settings.
    @State private var activeFormat: StripFormat

    @State private var image: UIImage?
    @State private var imageLoadError: String?
    /// Guards `initialImageData` so it's consumed only once. If the guest
    /// flips the format picker, we need to fetch the other format from
    /// storage rather than reusing the capture-time preview (which was
    /// rendered for the settings-default format).
    @State private var didConsumeInitialImage = false
    @State private var deliverySheet: StripService.DeliveryChannel?
    @State private var showDeleteConfirm = false
    @State private var showCopiesPicker = false
    @State private var statusMessage: String?
    @State private var isPerforming = false
    @State private var airDropPayload: AirDropPayload?
    @State private var idleTask: Task<Void, Never>?

    init(
        strip: Strip,
        initialImageData: Data? = nil,
        autoDismissOnInactivity: Bool = false,
        onDelete: @escaping (Strip) -> Void = { _ in }
    ) {
        self.strip = strip
        self.initialImageData = initialImageData
        self.autoDismissOnInactivity = autoDismissOnInactivity
        self.onDelete = onDelete
        self._activeFormat = State(initialValue: SettingsStore.shared.preferredFormat)
    }

    /// True whenever a sheet/alert is in front of the detail view. The
    /// idle timer pauses while this is true so the user isn't kicked out
    /// mid-compose.
    private var anySheetOpen: Bool {
        deliverySheet != nil || airDropPayload != nil || showDeleteConfirm || showCopiesPicker
    }

    /// Options shown in the "How many prints?" dialog. 2x6 strips are
    /// printed two-up on a 4x6 sheet and cut, so only even strip counts
    /// are physically achievable — the label reads in strips, the
    /// `copies` value is the sheet count sent to the print server.
    /// 4x6 prints go one sheet per copy, so 1..max as usual.
    private struct CopyOption: Identifiable {
        let copies: Int
        let label: String
        var id: Int { copies }
    }
    private var copyOptions: [CopyOption] {
        let maxCount = max(settings.maxPrintCopies, 1)
        switch activeFormat {
        case .twoBySix:
            // Floor to nearest even; guarantee at least one option (2
            // strips = 1 sheet) even if the operator set max to 1.
            let cap = max(2, maxCount - (maxCount % 2 == 0 ? 0 : 1))
            return stride(from: 2, through: cap, by: 2).map { strips in
                CopyOption(copies: strips / 2, label: "\(strips) strips")
            }
        case .fourBySix:
            return (1...maxCount).map { count in
                CopyOption(copies: count, label: count == 1 ? "1 copy" : "\(count) copies")
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            photoArea
            actionBar
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("Your strip")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                formatPicker
            }
        }
        .task { await loadImage() }
        .onChange(of: activeFormat) { _, _ in
            image = nil
            imageLoadError = nil
            Task { await loadImage() }
        }
        .onAppear { kickIdleTimer() }
        .onDisappear { cancelIdleTimer() }
        // Any tap on the view counts as engagement — simultaneousGesture
        // so it doesn't steal touches from the action buttons.
        .simultaneousGesture(
            TapGesture().onEnded { kickIdleTimer() }
        )
        // Sheet transitions are explicit user interactions. While a sheet
        // is open we pause the timer entirely; on close we re-arm.
        .onChange(of: anySheetOpen) { _, isOpen in
            if isOpen { cancelIdleTimer() } else { kickIdleTimer() }
        }
        // Full-screen cover rather than .sheet: on iPad, .sheet presents
        // in its own scene/window, so the software keyboard's placeholder
        // view ends up in a different hierarchy than the composer's text
        // field. Reopening the composer a second time throws an uncaught
        // "no common ancestor" NSLayoutConstraint exception and terminates
        // the app. .fullScreenCover keeps everything in the primary window.
        .fullScreenCover(item: $deliverySheet) { channel in
            DeliveryComposer(strip: strip, channel: channel) { msg in
                showStatus(msg)
            }
        }
        .sheet(item: $airDropPayload) { payload in
            AirDropSheet(fileURL: payload.url) { completed in
                airDropPayload = nil
                try? FileManager.default.removeItem(at: payload.url)
                if completed {
                    showStatus("Sent ✨")
                    Task {
                        await StripService.shared.logLocalAction(
                            strip: strip,
                            action: .airdrop
                        )
                    }
                }
            }
        }
        .alert("Delete this strip?", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { Task { await performDelete() } }
        } message: {
            Text("It'll be removed from the gallery. This can't be undone.")
        }
        .confirmationDialog(
            "How many prints?",
            isPresented: $showCopiesPicker,
            titleVisibility: .visible
        ) {
            ForEach(copyOptions, id: \.copies) { option in
                Button(option.label) {
                    Task { await performPrint(copies: option.copies) }
                }
            }
            Button("Cancel", role: .cancel) {}
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

    /// Menu that lets the guest flip between 2×6 and 4×6 for this strip.
    /// The Settings default only seeds this on open — the picker wins
    /// afterward and doesn't write back to SettingsStore.
    private var formatPicker: some View {
        Menu {
            Picker("Format", selection: $activeFormat) {
                ForEach(StripFormat.allCases) { format in
                    Text(format.displayName).tag(format)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(activeFormat.rawValue)
                    .font(.subheadline.weight(.semibold))
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.bold))
            }
            .foregroundStyle(Brand.pink)
        }
        .accessibilityLabel("Change format")
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
            actionButton(title: "AirDrop", icon: "square.and.arrow.up.fill", tint: Color.blue) {
                prepareAirDrop()
            }
            // Printing is gated only on the settings toggle. Server/printer
            // reachability is reflected through toasts on submit so the
            // button never silently disappears mid-event.
            if settings.printingEnabled {
                actionButton(title: "Print", icon: "printer.fill", tint: Brand.purple) {
                    let options = copyOptions
                    if options.count <= 1 {
                        // Only one achievable output — no reason to
                        // pop a picker with a single choice.
                        Task { await performPrint(copies: options.first?.copies ?? 1) }
                    } else {
                        showCopiesPicker = true
                    }
                }
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
        // Use the capture-flow's instant preview at most once. It matches
        // the settings-default format that was active at capture time, so
        // a later format flip must fall through to a storage download.
        if image != nil { return }
        if !didConsumeInitialImage,
           let data = initialImageData,
           let ui = UIImage(data: data) {
            didConsumeInitialImage = true
            image = ui
            return
        }
        do {
            let data = try await StripService.shared.downloadImageData(
                for: strip,
                format: activeFormat
            )
            image = UIImage(data: data)
        } catch {
            imageLoadError = error.localizedDescription
        }
    }

    // MARK: - Actions

    private func performPrint(copies: Int) async {
        guard let image else { return }
        isPerforming = true
        defer { isPerforming = false }
        do {
            _ = try await PrintService.shared.submit(
                image: image,
                format: activeFormat,
                copies: copies
            )
            showStatus("Sent to printer ✨")
            await StripService.shared.logLocalAction(strip: strip, action: .print)
        } catch {
            showStatus("Print failed: \(error.localizedDescription)")
        }
    }

    private func prepareAirDrop() {
        guard let image, let data = image.jpegData(compressionQuality: 0.92) else { return }
        let shortId = strip.id.uuidString.prefix(8).lowercased()
        let filename = "photoboot-\(activeFormat.rawValue)-\(shortId).jpg"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        do {
            try data.write(to: url, options: .atomic)
            airDropPayload = AirDropPayload(url: url)
        } catch {
            showStatus("Couldn't prep file: \(error.localizedDescription)")
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

    // MARK: - Idle auto-dismiss

    private func kickIdleTimer() {
        guard autoDismissOnInactivity, !anySheetOpen else { return }
        let seconds = settings.returnToCameraSeconds
        guard seconds > 0 else { return }
        idleTask?.cancel()
        idleTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds))
            if !Task.isCancelled, !anySheetOpen {
                dismiss()
            }
        }
    }

    private func cancelIdleTimer() {
        idleTask?.cancel()
        idleTask = nil
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
