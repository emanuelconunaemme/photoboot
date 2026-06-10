import AVFoundation
import UIKit
import os

@MainActor
final class CameraController: NSObject {
    let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private let sessionQueue = DispatchQueue(label: "xyz.saga.photoboot.camera")
    private let log = Logger(subsystem: "xyz.saga.photoboot", category: "camera")

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
        try await withCheckedThrowingContinuation { cont in
            self.captureContinuation = cont
            sessionQueue.async { [self] in
                let settings = AVCapturePhotoSettings()
                settings.flashMode = .off
                photoOutput.capturePhoto(with: settings, delegate: self)
            }
        }
    }

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
