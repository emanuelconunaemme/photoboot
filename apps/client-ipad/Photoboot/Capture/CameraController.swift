import AVFoundation
import UIKit
import os

@MainActor
final class CameraController: NSObject {
    let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private let sessionQueue = DispatchQueue(label: "com.mazzillie.photoboot.camera")
    private let log = Logger(subsystem: "com.mazzillie.photoboot", category: "camera")

    private var captureContinuation: CheckedContinuation<Data, Error>?

    enum CameraError: LocalizedError {
        case permissionDenied
        case configurationFailed
        case captureFailed(Error?)
        case noData

        var errorDescription: String? {
            switch self {
            case .permissionDenied: "Camera access is denied. Enable it in Settings."
            case .configurationFailed: "Couldn't set up the camera."
            case .captureFailed(let underlying): underlying?.localizedDescription ?? "Capture failed."
            case .noData: "Captured photo had no data."
            }
        }
    }

    func start() async throws {
        try await ensurePermission()
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            sessionQueue.async { [self] in
                if !session.isRunning {
                    do {
                        try configureSessionIfNeeded()
                        session.startRunning()
                    } catch {
                        log.error("Camera config failed: \(error.localizedDescription)")
                    }
                }
                cont.resume()
            }
        }
    }

    func stop() {
        sessionQueue.async { [session] in
            if session.isRunning { session.stopRunning() }
        }
    }

    func capture() async throws -> Data {
        #if targetEnvironment(simulator)
        // Simulator has no camera. Synthesize a recognizable image so the
        // upload + delivery flow can still be exercised end-to-end.
        return try synthesizeSimulatorImage()
        #else
        // Snapshot device orientation BEFORE leaving the main actor — UIDevice
        // is main-actor-isolated. The helper always returns a landscape angle
        // (the app is locked to landscape in Info.plist), so this just decides
        // landscape-left vs landscape-right.
        let rotationAngle = CameraOrientation.videoRotationAngle(
            for: UIDevice.current.orientation
        )
        return try await withCheckedThrowingContinuation { cont in
            self.captureContinuation = cont
            sessionQueue.async { [self] in
                for connection in photoOutput.connections
                where connection.isVideoRotationAngleSupported(rotationAngle) {
                    connection.videoRotationAngle = rotationAngle
                }
                let settings = AVCapturePhotoSettings()
                settings.flashMode = .off
                photoOutput.capturePhoto(with: settings, delegate: self)
            }
        }
        #endif
    }

    #if targetEnvironment(simulator)
    private func synthesizeSimulatorImage() throws -> Data {
        let size = CGSize(width: 1080, height: 1440)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            let colors = [UIColor.systemPink.cgColor, UIColor.systemOrange.cgColor]
            let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: colors as CFArray,
                locations: [0, 1]
            )!
            ctx.cgContext.drawLinearGradient(
                gradient,
                start: .zero,
                end: CGPoint(x: 0, y: size.height),
                options: []
            )

            let label = "SIMULATOR\n\(ISO8601DateFormatter().string(from: Date()))"
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 56, weight: .bold),
                .foregroundColor: UIColor.white,
                .paragraphStyle: paragraph,
            ]
            let textRect = CGRect(x: 40, y: size.height / 2 - 80, width: size.width - 80, height: 200)
            (label as NSString).draw(in: textRect, withAttributes: attrs)
        }
        guard let data = image.jpegData(compressionQuality: 0.9) else {
            throw CameraError.noData
        }
        return data
    }
    #endif

    // MARK: - Private

    private func ensurePermission() async throws {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            if !granted { throw CameraError.permissionDenied }
        case .denied, .restricted:
            throw CameraError.permissionDenied
        @unknown default:
            throw CameraError.permissionDenied
        }
    }

    private nonisolated func configureSessionIfNeeded() throws {
        // Called on sessionQueue. Idempotent.
        guard session.inputs.isEmpty else { return }

        session.beginConfiguration()
        session.sessionPreset = .photo

        let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
            ?? AVCaptureDevice.default(for: .video)
        guard let device else {
            session.commitConfiguration()
            throw CameraError.configurationFailed
        }

        do {
            let input = try AVCaptureDeviceInput(device: device)
            if session.canAddInput(input) {
                session.addInput(input)
            } else {
                session.commitConfiguration()
                throw CameraError.configurationFailed
            }

            if session.canAddOutput(photoOutput) {
                session.addOutput(photoOutput)
            } else {
                session.commitConfiguration()
                throw CameraError.configurationFailed
            }
        } catch {
            session.commitConfiguration()
            throw CameraError.configurationFailed
        }

        session.commitConfiguration()
    }
}

extension CameraController: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        Task { @MainActor in
            guard let cont = self.captureContinuation else { return }
            self.captureContinuation = nil

            if let error {
                cont.resume(throwing: CameraError.captureFailed(error))
                return
            }
            guard let data = photo.fileDataRepresentation() else {
                cont.resume(throwing: CameraError.noData)
                return
            }
            cont.resume(returning: data)
        }
    }
}
