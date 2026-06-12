import SwiftUI
import UIKit

// Renders a photo-booth-style strip composite from N captured images.
// Used at capture time to produce the JPEG we upload to the `composites` bucket.
struct StripView: View {
    let event: Event
    let photos: [UIImage]

    // Inner photo cell dimensions — landscape crop reads well at strip width.
    private let photoWidth: CGFloat = 720
    private let photoHeight: CGFloat = 480

    var body: some View {
        let primary = Color(hex: event.primaryColor)
        let secondary = Color(hex: event.secondaryColor)

        VStack(spacing: 12) {
            ForEach(photos.indices, id: \.self) { i in
                Image(uiImage: photos[i])
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: photoWidth, height: photoHeight)
                    .clipped()
                    .clipShape(.rect(cornerRadius: 10))
            }

            VStack(spacing: 6) {
                Text(event.name)
                    .font(.system(size: 36, weight: .heavy))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                if let dateText = formattedDate {
                    Text(dateText)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(.white.opacity(0.9))
                }
            }
            .frame(width: photoWidth)
            .padding(.vertical, 18)
            .background(
                LinearGradient(
                    colors: [primary, secondary],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .clipShape(.rect(cornerRadius: 10))
        }
        .padding(20)
        .background(Color.white)
    }

    private var formattedDate: String? {
        guard let date = event.eventDateValue else { return nil }
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        return formatter.string(from: date)
    }
}

@MainActor
enum StripRenderer {
    static func render(event: Event, photos: [UIImage]) -> Data? {
        let view = StripView(event: event, photos: photos)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2.0
        guard let uiImage = renderer.uiImage else { return nil }
        return uiImage.jpegData(compressionQuality: 0.88)
    }
}
