import SwiftUI

struct DeliveryComposer: View {
    let strip: Strip
    let channel: StripService.DeliveryChannel
    let onSent: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var settings = SettingsStore.shared
    @State private var recipient = ""
    @State private var isSending = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()
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

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.callout)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                    }

                    if channel == .sms && settings.showSmsConsent {
                        // Twilio toll-free verification language: identify the
                        // sender, set frequency expectation, mention rates, and
                        // give an opt-out method. Toggled by Settings.
                        // fixedSize lets the text wrap to as many lines as it
                        // needs instead of getting clipped to one line.
                        Text("By entering your number, you consent to one text from Blocktech Ventures with your photo link. Msg & data rates may apply. Reply STOP to cancel.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 4)
                    }

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

                    Spacer()
                }
                .padding(24)
            }
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
        isSending = true
        Task {
            defer { isSending = false }
            do {
                try await StripService.shared.createDelivery(
                    strip: strip,
                    channel: channel,
                    recipient: trimmed
                )
                onSent("Queued for \(trimmed) 💌")
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
