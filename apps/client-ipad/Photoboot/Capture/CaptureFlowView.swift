import SwiftUI

@MainActor
struct CaptureFlowView: View {
    let event: Event

    @State private var camera = CameraController()
    @State private var uploader = StripUploader()
    @State private var phase: Phase = .idle
    @State private var countdown = 3
    @State private var shotsTaken: [Data] = []
    @State private var uploadedStrip: Strip?
    @State private var errorMessage: String?

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
            CameraPreviewView(session: camera.session)
                .ignoresSafeArea()
        case .review, .uploading:
            reviewBackground
        }
    }

    private var reviewBackground: some View {
        ScrollView {
            VStack(spacing: 12) {
                ForEach(shotsTaken.indices, id: \.self) { i in
                    if let img = UIImage(data: shotsTaken[i]) {
                        Image(uiImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(maxWidth: .infinity)
                            .frame(height: 260)
                            .clipped()
                            .clipShape(.rect(cornerRadius: 16))
                    }
                }
                Color.clear.frame(height: 180)
            }
            .padding(20)
            .padding(.top, 60)
        }
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
                .foregroundStyle(.white)
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
        let n = event.shotsPerStrip
        return n == 1 ? "One photo strip" : "\(n) photos · \(n - 1) quick pauses"
    }

    private var progressDots: some View {
        HStack(spacing: 10) {
            ForEach(0..<event.shotsPerStrip, id: \.self) { i in
                Circle()
                    .fill(
                        i < shotsTaken.count
                            ? AnyShapeStyle(Brand.gradient)
                            : AnyShapeStyle(Color.white.opacity(0.3))
                    )
                    .frame(width: 14, height: 14)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.black.opacity(0.45), in: .capsule)
    }

    private var captureButton: some View {
        Button(action: startCountdownChain) {
            ZStack {
                Circle().fill(.white).frame(width: 96, height: 96)
                Circle()
                    .stroke(Brand.gradient, lineWidth: 6)
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
            for shotIndex in 1...event.shotsPerStrip {
                phase = .counting
                countdown = 3
                while countdown > 0 {
                    try? await Task.sleep(for: .seconds(1))
                    countdown -= 1
                }
                do {
                    let data = try await camera.capture()
                    shotsTaken.append(data)
                    if shotIndex < event.shotsPerStrip {
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

    /// Renders the same StripView client-side so the detail screen can show
    /// the composite instantly without waiting for the signed-URL round-trip.
    private func lastCompositePreviewData() -> Data? {
        let images = shotsTaken.compactMap { UIImage(data: $0) }
        guard !images.isEmpty else { return nil }
        return StripRenderer.render(event: event, photos: images)
    }

    private func reset() {
        shotsTaken = []
        uploadedStrip = nil
        errorMessage = nil
        phase = .idle
    }
}
