import SwiftUI
import UIKit

/// Idle attractor: displays the branded right half of the 4×6 background
/// (the side without photos) full-screen on the portrait iPad. The
/// right half is 900×1200 → 3:4 aspect, which matches the iPad's
/// portrait screen so it fills cleanly with no letterboxing.
struct SplashView: View {
    let event: Event

    // Holding the cache in @State guarantees SwiftUI's Observation
    // machinery tracks property reads on the @Observable singleton.
    // Without this, body re-eval on cache mutation is unreliable.
    @State private var cache = BackgroundCache.shared

    var body: some View {
        ZStack {
            if let bg = cache.image(for: event.backgroundPath4x6),
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
        .overlay(alignment: .bottom) {
            TapToStartHint()
                .padding(.bottom, 80)
        }
        .contentShape(Rectangle())
        // Last-resort load: if for any reason the cache is still empty when
        // the splash actually appears, kick a preload here. cache.load() is
        // idempotent + coalescing, so calling it again is cheap.
        .task {
            await cache.preload(for: event)
        }
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

/// Pulsing "Tap to start" pill — gentle attractor so first-time guests
/// know the splash is interactive. Wraps in Brand.gradient to stay
/// on-brand against whatever the host designed into the template.
private struct TapToStartHint: View {
    @State private var pulse = false

    var body: some View {
        Text("Tap to start ✨")
            .font(.system(size: 40, weight: .heavy, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 48)
            .padding(.vertical, 24)
            .background(Brand.gradient, in: .capsule)
            .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
            .scaleEffect(pulse ? 1.06 : 1.0)
            .opacity(pulse ? 1.0 : 0.85)
            .onAppear {
                withAnimation(
                    .easeInOut(duration: 1.2).repeatForever(autoreverses: true)
                ) {
                    pulse = true
                }
            }
    }
}
