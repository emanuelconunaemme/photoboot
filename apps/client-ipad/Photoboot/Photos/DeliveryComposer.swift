import SwiftUI
import UIKit

struct DeliveryComposer: View {
    let strip: Strip
    let channel: StripService.DeliveryChannel
    let onSent: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var settings = SettingsStore.shared
    @State private var recipients = RecipientStore.shared
    @State private var recipient = ""
    @State private var isSending = false
    @State private var errorMessage: String?

    private var suggestions: [RecipientSuggestion] {
        recipients.suggestions(
            for: strip.eventId,
            channel: channel,
            prefix: recipient
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    header

                    // Text field lives inline at the top of the sheet —
                    // above the keyboard's docked area — so the guest can
                    // always see what they've typed. Suggestions read
                    // naturally below it.
                    inputBar

                    if !suggestions.isEmpty {
                        SuggestionList(items: suggestions) { picked in
                            recipient = picked.value
                        }
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.callout)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if channel == .sms && settings.showSmsConsent {
                        // Twilio toll-free verification language: identify
                        // the sender, set frequency expectation, mention
                        // rates, give an opt-out method, link to Terms +
                        // Privacy. Toggled by Settings.
                        VStack(spacing: 10) {
                            Text("By entering your number, you consent to one text from Blocktech Ventures with your photo link. Msg & data rates may apply. Reply STOP to cancel.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .lineLimit(nil)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity)

                            HStack(spacing: 14) {
                                Link("Terms", destination: URL(string: "https://photoboot.mazzillie.com/terms")!)
                                Text("·").foregroundStyle(.tertiary)
                                Link("Privacy", destination: URL(string: "https://photoboot.mazzillie.com/privacy")!)
                            }
                            .font(.footnote.weight(.medium))
                            .tint(Brand.pink)
                        }
                        .padding(.horizontal, 4)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle(channel.displayTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private var inputBar: some View {
        HStack(spacing: 10) {
            RecipientField(
                text: $recipient,
                placeholder: channel.inputPlaceholder,
                keyboardType: channel == .email ? .emailAddress : .numberPad,
                contentType: channel == .email ? .emailAddress : nil,
                isEnabled: !isSending,
                onSubmit: send
            )
            .frame(minHeight: 28)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(.background, in: .rect(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Brand.pink.opacity(0.4), lineWidth: 1.5)
            )

            Button(action: send) {
                Group {
                    if isSending {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 20, weight: .bold))
                    }
                }
                .frame(width: 52, height: 52)
                .background(Brand.gradient, in: .circle)
                .foregroundStyle(.white)
            }
            .disabled(recipient.trimmingCharacters(in: .whitespaces).isEmpty || isSending)
            .opacity(recipient.trimmingCharacters(in: .whitespaces).isEmpty ? 0.55 : 1)
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle().fill(Brand.gradient).frame(width: 64, height: 64)
                Image(systemName: channel.systemImage)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.white)
            }
            Text(channel == .email ? "Where should we send it?" : "What's their number?")
                .font(.headline)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 8)
    }

    private func send() {
        errorMessage = nil
        let trimmed = recipient.trimmingCharacters(in: .whitespaces)
        let normalized = channel == .sms ? normalizeUSPhone(trimmed) : trimmed
        isSending = true
        Task {
            defer { isSending = false }
            do {
                try await StripService.shared.createDelivery(
                    strip: strip,
                    channel: channel,
                    recipient: normalized
                )
                // Save to contacts in the background so future events
                // (and this one's autocomplete) see the recipient. Fire
                // and forget — never blocks the user's send.
                Task {
                    await RecipientStore.shared.recordManual(
                        value: normalized,
                        eventId: strip.eventId,
                        channel: channel
                    )
                }
                onSent(channel == .sms ? "Sending SMS… 💌" : "Sending email… 💌")
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

/// Suggestion picker shown under the recipient field. Tap a row to fill.
private struct SuggestionList: View {
    let items: [RecipientSuggestion]
    let onPick: (RecipientSuggestion) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                Button { onPick(item) } label: {
                    HStack(spacing: 10) {
                        Text(item.value)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 8)
                        Text(item.origin.label)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(.secondary.opacity(0.12), in: .capsule)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if index < items.count - 1 {
                    Divider().padding(.leading, 16)
                }
            }
        }
        .background(.background, in: .rect(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
        )
    }
}

// Defaults to US (+1) when the guest omits a country code — most events
// are local. Anyone entering an international number must type the +.
private func normalizeUSPhone(_ raw: String) -> String {
    if raw.hasPrefix("+") {
        return "+" + raw.dropFirst().filter(\.isNumber)
    }
    return "+1" + raw.filter(\.isNumber)
}

/// UIKit-backed text field for the delivery composer. The SwiftUI
/// TextField on iPad silently attaches keyboard accessory views
/// (QuickType, Writing Tools, autofill chips) that iOS re-anchors to
/// `_UIRemoteKeyboardPlaceholderView` asynchronously — during a modal
/// presentation the two live in different view hierarchies and UIKit
/// throws an uncaught "no common ancestor" NSLayoutConstraint exception
/// that terminates the app. Wrapping UITextField lets us clear the
/// input-assistant bar groups and turn off every smart-editing feature
/// explicitly, which suppresses all the accessory-view paths at once.
struct RecipientField: UIViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let keyboardType: UIKeyboardType
    let contentType: UITextContentType?
    let isEnabled: Bool
    let onSubmit: () -> Void

    func makeUIView(context: Context) -> UITextField {
        let tf = UITextField()
        tf.placeholder = placeholder
        tf.keyboardType = keyboardType
        tf.textContentType = contentType
        tf.autocorrectionType = .no
        tf.autocapitalizationType = .none
        tf.spellCheckingType = .no
        tf.smartQuotesType = .no
        tf.smartDashesType = .no
        tf.smartInsertDeleteType = .no
        tf.returnKeyType = .send
        tf.font = UIFont.preferredFont(forTextStyle: .body)
        tf.borderStyle = .none
        tf.setContentHuggingPriority(.defaultLow, for: .horizontal)
        tf.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        // Clear the floating keyboard accessory bar on iPad. This is
        // what the SwiftUI-only path leaks and what triggers the
        // _UIRemoteKeyboardPlaceholderView constraint crash.
        tf.inputAssistantItem.leadingBarButtonGroups = []
        tf.inputAssistantItem.trailingBarButtonGroups = []
        tf.inputAccessoryView = nil
        // Disable Writing Tools (iOS 18+) on this field — it's the
        // other iPad accessory that reparents itself onto the keyboard
        // placeholder view.
        if #available(iOS 18.0, *) {
            tf.writingToolsBehavior = .none
        }
        tf.delegate = context.coordinator
        tf.addTarget(
            context.coordinator,
            action: #selector(Coordinator.editingChanged(_:)),
            for: .editingChanged
        )
        // Defer first-responder to the next runloop so it doesn't race
        // with the fullScreenCover's presentation animation — that race
        // is itself a common trigger for the placeholder-view crash.
        DispatchQueue.main.async { [weak tf] in
            tf?.becomeFirstResponder()
        }
        return tf
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }
        uiView.isEnabled = isEnabled
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onSubmit: onSubmit)
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        @Binding var text: String
        let onSubmit: () -> Void

        init(text: Binding<String>, onSubmit: @escaping () -> Void) {
            _text = text
            self.onSubmit = onSubmit
        }

        @objc func editingChanged(_ textField: UITextField) {
            text = textField.text ?? ""
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            onSubmit()
            return true
        }
    }
}
