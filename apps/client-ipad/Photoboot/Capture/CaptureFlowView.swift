import SwiftUI

@MainActor
struct CaptureFlowView: View {
    let event: Event

    @State private var camera = CameraController()
    @State private var uploader = PhotoUploader()
    @State private var phase: Phase = .idle
    @State private var countdown = 3
    @State private var capturedImageData: Data?
    @State private var errorMessage: String?

    enum Phase {
        case idle
        case counting
        case review
        case uploading
        case uploaded
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let data = capturedImageData, let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
                    .ignoresSafeArea()
            } else {
                CameraPreviewView(session: camera.session)
                    .ignoresSafeArea()
            }

            VStack {
                Spacer()
                overlay
                    .padding(.bottom, 60)
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
    }

    @ViewBuilder
    private var overlay: some View {
        switch phase {
        case .idle:
            captureButton
        case .counting:
            Text("\(countdown)")
                .font(.system(size: 240, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .shadow(radius: 8)
        case .review:
            reviewButtons
        case .uploading:
            ProgressView("Uploading…").tint(.white).foregroundStyle(.white)
        case .uploaded:
            VStack(spacing: 16) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(.green)
                Text("Sent!").font(.title.weight(.semibold)).foregroundStyle(.white)
                Button("Take another", action: reset)
                    .buttonStyle(.borderedProminent)
                    .tint(.white)
                    .foregroundStyle(.black)
            }
        }
    }

    private var captureButton: some View {
        Button(action: startCountdown) {
            ZStack {
                Circle().fill(.white).frame(width: 96, height: 96)
                Circle().stroke(.white, lineWidth: 4).frame(width: 110, height: 110)
            }
        }
        .disabled(errorMessage != nil)
        .overlay(alignment: .bottom) {
            if let errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.white)
                    .padding(8)
                    .background(.red.opacity(0.85), in: .rect(cornerRadius: 8))
                    .padding(.top, 12)
                    .offset(y: 80)
            }
        }
    }

    private var reviewButtons: some View {
        HStack(spacing: 24) {
            Button("Retake", action: reset)
                .buttonStyle(.bordered)
                .tint(.white)
                .controlSize(.extraLarge)

            Button("Send it", action: upload)
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .controlSize(.extraLarge)
        }
    }

    private func startCountdown() {
        errorMessage = nil
        phase = .counting
        countdown = 3
        Task {
            while countdown > 0 {
                try? await Task.sleep(for: .seconds(1))
                countdown -= 1
            }
            await capture()
        }
    }

    private func capture() async {
        do {
            let data = try await camera.capture()
            capturedImageData = data
            phase = .review
        } catch {
            errorMessage = error.localizedDescription
            phase = .idle
        }
    }

    private func upload() {
        guard let data = capturedImageData else { return }
        phase = .uploading
        Task {
            do {
                try await uploader.upload(imageData: data, for: event)
                phase = .uploaded
            } catch {
                errorMessage = error.localizedDescription
                phase = .review
            }
        }
    }

    private func reset() {
        capturedImageData = nil
        errorMessage = nil
        phase = .idle
    }
}
