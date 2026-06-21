import SwiftUI

@MainActor
struct CaptureFlowView: View {
    let event: Event

    @State private var camera = CameraController()
    @State private var uploader = StripUploader()
    @State private var settings = SettingsStore.shared
    @State private var phase: Phase = .idle
    @State private var countdown = 3
    @State private var shotsTaken: [Data] = []
    @State private var uploadedStrip: Strip?
    @State private var errorMessage: String?

    private let shotsTotal = 2

    enum Phase {
        case idle
        case counting
        case review
        case uploading
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            backgroundView

            VStack {
                if phase == .counting || phase == .review {
                    progressDots
                        .padding(.top, 16)
                }
                Spacer()
                overlay
                    .padding(.bottom, 60)
            }

            if let errorMessage {
                VStack {
                    Text(errorMessage)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(12)
                        .background(.red.opacity(0.9), in: .rect(cornerRadius: 10))
                        .padding(.horizontal, 24)
                        .padding(.top, 80)
                    Spacer()
                }
            }
        }
        .navigationTitle(event.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.black, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task {
            do { try await camera.start() }
            catch { errorMessage = error.localizedDescription }
        }
        .onDisappear { camera.stop() }
        .fullScreenCover(item: $uploadedStrip, onDismiss: reset) { strip in
            NavigationStack {
                StripDetailView(strip: strip, initialImageData: lastCompositePreviewData())
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Done") { uploadedStrip = nil }
                        }
                    }
            }
        }
    }

    @ViewBuilder
    private var backgroundView: some View {
        switch phase {
        case .idle, .counting:
            // Frame the preview at the strip's 3:2 landscape aspect so the
            // user only sees the region that will actually land in the
            // composite. The portrait capture is wider than this slice, but
            // every strip cell crops down to a horizontal band ≤ 3:2 — so
            // whatever you can see here is guaranteed to be in both prints.
            CameraPreviewView(session: camera.session)
                .aspectRatio(3.0 / 2.0, contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .review, .uploading:
            reviewBackground
        }
    }

    /// Two captures stacked vertically, each at the strip's landscape
    /// aspect (6:4 = 3:2). Sized so both fit in the available height
    /// above the action buttons. No background, no composite — just the
    /// shots cropped to the print aspect so the user can see whether
    /// faces are well-framed.
    private var reviewBackground: some View {
        GeometryReader { proxy in
            let gap: CGFloat = 16
            let availableHeight = proxy.size.height
            let perHeight = max((availableHeight - gap) / 2, 100)
            let perWidth = min(perHeight * 3.0 / 2.0, proxy.size.width)

            VStack(spacing: gap) {
                ForEach(shotsTaken.indices, id: \.self) { i in
                    if let img = UIImage(data: shotsTaken[i]) {
                        Color.clear
                            .frame(width: perWidth, height: perHeight)
                            .overlay {
                                Image(uiImage: img)
                                    .resizable()
                                    .scaledToFill()
                            }
                            .clipShape(.rect(cornerRadius: 14))
                            .shadow(color: .black.opacity(0.3), radius: 10, y: 4)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.top, 60)
        .padding(.bottom, 160)
        .padding(.horizontal, 20)
    }

    @ViewBuilder
    private var overlay: some View {
        switch phase {
        case .idle:
            VStack(spacing: 12) {
                Text(idleSubtitle)
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.85))
                captureButton
            }
        case .counting:
            Text("\(countdown)")
                .font(.system(size: 240, weight: .black, design: .rounded))
                .foregroundStyle(countdownColor)
                .shadow(radius: 8)
                .contentTransition(.numericText(value: Double(countdown)))
        case .review:
            reviewButtons
        case .uploading:
            ProgressView("Building your strip…")
                .tint(.white)
                .foregroundStyle(.white)
                .controlSize(.large)
        }
    }

    private var idleSubtitle: String {
        "2 photos · \(settings.firstCountdownSeconds)s then \(settings.nextCountdownSeconds)s"
    }

    private var countdownColor: Color {
        let shotNumber = shotsTaken.count + 1
        return shotNumber.isMultiple(of: 2)
            ? Brand.eventSecondary(for: event)
            : Brand.eventPrimary(for: event)
    }

    private var progressDots: some View {
        HStack(spacing: 10) {
            ForEach(0..<shotsTotal, id: \.self) { i in
                Circle()
                    .fill(dotColor(at: i))
                    .frame(width: 14, height: 14)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.black.opacity(0.45), in: .capsule)
    }

    private func dotColor(at index: Int) -> Color {
        guard index < shotsTaken.count else { return .white.opacity(0.3) }
        let shotNumber = index + 1
        return shotNumber.isMultiple(of: 2)
            ? Brand.eventSecondary(for: event)
            : Brand.eventPrimary(for: event)
    }

    private var captureButton: some View {
        Button(action: startCountdownChain) {
            ZStack {
                Circle().fill(.white).frame(width: 96, height: 96)
                Circle()
                    .stroke(Brand.eventGradient(for: event), lineWidth: 6)
                    .frame(width: 110, height: 110)
            }
        }
    }

    private var reviewButtons: some View {
        HStack(spacing: 24) {
            Button("Retake all", action: reset)
                .buttonStyle(.bordered)
                .tint(.white)
                .controlSize(.extraLarge)

            Button(action: upload) {
                Text("Send it").fontWeight(.semibold)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(Brand.pink)
            .controlSize(.extraLarge)
        }
    }

    // MARK: - Flow

    private func startCountdownChain() {
        errorMessage = nil
        shotsTaken = []
        Task {
            for shotIndex in 1...shotsTotal {
                phase = .counting
                countdown = shotIndex == 1
                    ? settings.firstCountdownSeconds
                    : settings.nextCountdownSeconds
                while countdown > 0 {
                    try? await Task.sleep(for: .seconds(1))
                    countdown -= 1
                }
                do {
                    let data = try await camera.capture()
                    shotsTaken.append(data)
                    if shotIndex < shotsTotal {
                        try? await Task.sleep(for: .milliseconds(350))
                    }
                } catch {
                    errorMessage = error.localizedDescription
                    phase = .idle
                    return
                }
            }
            phase = .review
        }
    }

    private func upload() {
        guard !shotsTaken.isEmpty else { return }
        phase = .uploading
        Task {
            do {
                let strip = try await uploader.upload(rawPhotos: shotsTaken, for: event)
                uploadedStrip = strip
            } catch {
                errorMessage = error.localizedDescription
                phase = .review
            }
        }
    }

    /// Renders the user's preferred format client-side so the detail screen
    /// shows the strip instantly. Backgrounds were preloaded by
    /// BackgroundCache when entering the event, so this is fast.
    private func lastCompositePreviewData() -> Data? {
        let images = shotsTaken.compactMap { UIImage(data: $0) }
        guard !images.isEmpty else { return nil }
        return StripRenderer.render(
            event: event,
            photos: images,
            format: settings.preferredFormat
        )
    }

    private func reset() {
        shotsTaken = []
        uploadedStrip = nil
        errorMessage = nil
        phase = .idle
    }
}
