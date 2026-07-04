import SwiftUI
import UIKit

// MARK: - 2×6 strip (portrait, 1:3 aspect)

struct StripView2x6: View {
    let event: Event
    let photos: [UIImage]
    let backgroundImage: UIImage?

    private let canvasWidth: CGFloat = 600
    private let canvasHeight: CGFloat = 1800
    // 4:3 landscape — close enough to the 3:2 capture to crop only ~5% off
    // each edge, keeps the photos prominent in the tall 2×6 strip. Sized
    // at ~95% of the earlier 552×414 to leave a bit more background around
    // each photo (VStack Spacers keep them centered vertically).
    private let photoWidth: CGFloat = 524
    private let photoHeight: CGFloat = 393

    var body: some View {
        ZStack {
            background
            // Photos centered vertically — the background template carries
            // its own header above and footer below the photo pair.
            VStack(spacing: 24) {
                Spacer(minLength: 0)
                ForEach(photos.prefix(2).indices, id: \.self) { i in
                    Image(uiImage: photos[i])
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: photoWidth, height: photoHeight)
                        .clipped()
                        .clipShape(.rect(cornerRadius: 12))
                }
                Spacer(minLength: 0)
            }
            .padding(24)
        }
        .frame(width: canvasWidth, height: canvasHeight)
    }

    @ViewBuilder
    private var background: some View {
        if let bg = backgroundImage {
            Image(uiImage: bg)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: canvasWidth, height: canvasHeight)
                .clipped()
        } else {
            LinearGradient(
                colors: [Color(hex: event.primaryColor), Color(hex: event.secondaryColor)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}

// MARK: - 4×6 print (landscape, 3:2 aspect)

struct StripView4x6: View {
    let event: Event
    let photos: [UIImage]
    let backgroundImage: UIImage?

    private let canvasWidth: CGFloat = 1800
    private let canvasHeight: CGFloat = 1200

    // 3:2 landscape cells — match the captures' 3:2 aspect exactly, no crop.
    // Two stacked vertically in the left half.
    private let photoWidth: CGFloat = 810
    private let photoHeight: CGFloat = 540

    var body: some View {
        ZStack {
            background
            HStack(spacing: 0) {
                VStack(spacing: 30) {
                    ForEach(photos.prefix(2).indices, id: \.self) { i in
                        Image(uiImage: photos[i])
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: photoWidth, height: photoHeight)
                            .clipped()
                            .clipShape(.rect(cornerRadius: 14))
                    }
                }
                .frame(width: canvasWidth / 2)
                // Nudge photos toward the center so the paper's left edge
                // isn't hugging the images (75px was too tight visually).
                .offset(x: 40)

                // Right half intentionally empty so the background image's
                // own title / artwork / branding shows through.
                Color.clear
                    .frame(width: canvasWidth / 2)
            }
            .padding(30)
        }
        .frame(width: canvasWidth, height: canvasHeight)
    }

    @ViewBuilder
    private var background: some View {
        if let bg = backgroundImage {
            Image(uiImage: bg)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: canvasWidth, height: canvasHeight)
                .clipped()
        } else {
            LinearGradient(
                colors: [Color(hex: event.primaryColor), Color(hex: event.secondaryColor)],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
    }
}

// MARK: - Renderer

@MainActor
enum StripRenderer {
    /// Renders both formats from the same raw photos + event metadata.
    /// Backgrounds are read from the BackgroundCache — caller is expected to
    /// have preloaded them already (e.g., via `BackgroundCache.preload(for:)`).
    static func renderBoth(event: Event, photos: [UIImage]) -> (twoBySix: Data?, fourBySix: Data?) {
        let bg2x6 = BackgroundCache.shared.image(for: event.backgroundPath2x6)
        let bg4x6 = BackgroundCache.shared.image(for: event.backgroundPath4x6)
        let v2x6 = StripView2x6(event: event, photos: photos, backgroundImage: bg2x6)
        let v4x6 = StripView4x6(event: event, photos: photos, backgroundImage: bg4x6)
        return (renderToData(v2x6), renderToData(v4x6))
    }

    /// Renders a single format — used by CaptureFlowView for the instant
    /// preview shown on the detail screen before the upload finishes.
    static func render(event: Event, photos: [UIImage], format: StripFormat) -> Data? {
        let bgPath = event.backgroundPath(for: format)
        let bg = BackgroundCache.shared.image(for: bgPath)
        switch format {
        case .twoBySix:
            return renderToData(StripView2x6(event: event, photos: photos, backgroundImage: bg))
        case .fourBySix:
            return renderToData(StripView4x6(event: event, photos: photos, backgroundImage: bg))
        }
    }

    private static func renderToData<V: View>(_ view: V) -> Data? {
        renderToImage(view)?.jpegData(compressionQuality: 0.88)
    }

    private static func renderToImage<V: View>(_ view: V) -> UIImage? {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2.0
        return renderer.uiImage
    }
}
