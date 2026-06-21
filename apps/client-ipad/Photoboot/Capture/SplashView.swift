import SwiftUI
import UIKit

/// Idle attractor: displays the branded right half of the 4×6 background
/// (the side without photos) full-screen on the portrait iPad. The
/// right half is 900×1200 → 3:4 aspect, which matches the iPad's
/// portrait screen so it fills cleanly with no letterboxing.
struct SplashView: View {
    let event: Event

    var body: some View {
        ZStack {
            if let bg = BackgroundCache.shared.image(for: event.backgroundPath4x6),
               let rightHalf = Self.cropRightHalf(bg) {
                Image(uiImage: rightHalf)
                    .resizable()
                    .scaledToFill()
                    .ignoresSafeArea()
            } else {
                // Fallback if the background hasn't loaded yet (or this
                // event has no 4×6 template configured).
                LinearGradient(
                    colors: [
                        Color(hex: event.primaryColor),
                        Color(hex: event.secondaryColor),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
            }
        }
        .contentShape(Rectangle())
    }

    private static func cropRightHalf(_ image: UIImage) -> UIImage? {
        guard let cg = image.cgImage else { return nil }
        let rect = CGRect(
            x: cg.width / 2,
            y: 0,
            width: cg.width / 2,
            height: cg.height
        )
        guard let cropped = cg.cropping(to: rect) else { return nil }
        return UIImage(
            cgImage: cropped,
            scale: image.scale,
            orientation: image.imageOrientation
        )
    }
}
