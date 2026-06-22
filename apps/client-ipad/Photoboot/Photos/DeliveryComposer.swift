import SwiftUI

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
            VStack(spacing: 0) {
                // Scrollable content area — grows with consent text or
                // long error messages without pushing the Send button off
                // the bottom of the sheet.
                ScrollView {
                    VStack(spacing: 24) {
                        header

                        TextField(channel.inputPlaceholder, text: $recipient)
                            .keyboardType(channel == .email ? .emailAddress : .phonePad)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding(16)
                            .background(.background, in: .rect(cornerRadius: 14))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(Brand.pink.opacity(0.4), lineWidth: 1.5)
                            )

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

                // Sticky Send button area. Padding here is consistent whether
                // or not the consent block is showing, so the button always
                // sits the same distance from the bottom of the sheet.
                Button(action: send) {
                    HStack(spacing: 10) {
                        if isSending {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: "paperplane.fill")
                        }
                        Text(isSending ? "Sending…" : "Send")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Brand.gradient, in: .rect(cornerRadius: 14))
                    .foregroundStyle(.white)
                }
                .disabled(recipient.trimmingCharacters(in: .whitespaces).isEmpty || isSending)
                .opacity(recipient.trimmingCharacters(in: .whitespaces).isEmpty ? 0.55 : 1)
                .padding(.horizontal, 24)
                .padding(.top, 12)
                .padding(.bottom, 24)
                .background(.background)
                .overlay(alignment: .top) {
                    Divider().opacity(0.4)
                }
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
