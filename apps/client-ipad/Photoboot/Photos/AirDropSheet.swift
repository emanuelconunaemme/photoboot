import SwiftUI
import UIKit

struct AirDropPayload: Identifiable {
    let url: URL
    var id: URL { url }
}

// AirDrop-only on purpose: this iPad is the shared kiosk, so "Save to Photos"
// / "Mail" / etc would write to the kiosk's library or accounts instead of the
// guest's device. AirDrop is the only option that cleanly hands the file off.
struct AirDropSheet: UIViewControllerRepresentable {
    let fileURL: URL
    let onComplete: (Bool) -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(
            activityItems: [fileURL],
            applicationActivities: nil
        )
        controller.excludedActivityTypes = nonAirDropActivities
        controller.completionWithItemsHandler = { _, completed, _, _ in
            onComplete(completed)
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

private let nonAirDropActivities: [UIActivity.ActivityType] = [
    .addToReadingList,
    .assignToContact,
    .copyToPasteboard,
    .mail,
    .markupAsPDF,
    .message,
    .openInIBooks,
    .postToFacebook,
    .postToFlickr,
    .postToTencentWeibo,
    .postToTwitter,
    .postToVimeo,
    .postToWeibo,
    .print,
    .saveToCameraRoll,
    .sharePlay,
]
