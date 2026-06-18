import AVFoundation
import SwiftUI
import UIKit

struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        view.startTrackingOrientation()
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.previewLayer.session = session
        uiView.applyCurrentRotation()
    }

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }

        func startTrackingOrientation() {
            UIDevice.current.beginGeneratingDeviceOrientationNotifications()
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(orientationDidChange),
                name: UIDevice.orientationDidChangeNotification,
                object: nil
            )
            applyCurrentRotation()
        }

        @objc private func orientationDidChange() {
            applyCurrentRotation()
        }

        func applyCurrentRotation() {
            guard let connection = previewLayer.connection else { return }
            let angle = CameraOrientation.videoRotationAngle(for: UIDevice.current.orientation)
            if connection.isVideoRotationAngleSupported(angle) {
                connection.videoRotationAngle = angle
            }
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }
    }
}

// Shared helper used by both the preview layer and the photo output to map
// device orientation → AVCaptureConnection.videoRotationAngle (degrees).
//
// The app is locked to portrait in Info.plist (front camera sits at the top
// long edge, so landscape framing is awkward). The default protects against
// transient .unknown / .faceUp / .faceDown states during launch.
enum CameraOrientation {
    static func videoRotationAngle(for orientation: UIDeviceOrientation) -> CGFloat {
        switch orientation {
        case .portrait: 90
        case .portraitUpsideDown: 270
        default: 90
        }
    }
}
