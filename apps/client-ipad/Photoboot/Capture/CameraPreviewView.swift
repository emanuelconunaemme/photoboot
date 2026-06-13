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
            guard let connection = previewLayer.connection,
                  let angle = CameraOrientation.videoRotationAngle(for: UIDevice.current.orientation)
            else { return }
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
enum CameraOrientation {
    static func videoRotationAngle(for orientation: UIDeviceOrientation) -> CGFloat? {
        switch orientation {
        case .portrait: 90
        case .portraitUpsideDown: 270
        case .landscapeLeft: 0       // home button on the right
        case .landscapeRight: 180    // home button on the left
        default: nil                 // .unknown / .faceUp / .faceDown — keep last
        }
    }
}
