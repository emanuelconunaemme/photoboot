import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var settings = SettingsStore.shared
    @State private var printService = PrintService.shared

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Print format", selection: $settings.preferredFormat) {
                        ForEach(StripFormat.allCases) { format in
                            Text(format.displayName).tag(format)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Format")
                } footer: {
                    Text("Both formats are always rendered + uploaded. This picks the one the iPad shows in the gallery and prints.")
                }

                Section {
                    Stepper(
                        "First countdown: \(settings.firstCountdownSeconds)s",
                        value: $settings.firstCountdownSeconds,
                        in: 1...10
                    )
                    Stepper(
                        "Between shots: \(settings.nextCountdownSeconds)s",
                        value: $settings.nextCountdownSeconds,
                        in: 1...10
                    )
                } header: {
                    Text("Countdowns")
                } footer: {
                    Text("Seconds before the first shot, and between each pair of shots.")
                }

                Section {
                    Toggle("Show SMS consent message", isOn: $settings.showSmsConsent)
                } header: {
                    Text("SMS")
                } footer: {
                    Text("Required language for Twilio toll-free verification. Keep on while sending to US numbers; turn off only if your sending number is already verified for transactional photo-delivery use.")
                }

                Section {
                    Stepper(
                        settings.splashDelaySeconds == 0
                            ? "Splash screen: off"
                            : "Splash after: \(settings.splashDelaySeconds)s",
                        value: $settings.splashDelaySeconds,
                        in: 0...60,
                        step: 5
                    )
                } header: {
                    Text("Splash screen")
                } footer: {
                    Text("Idle attractor that takes over the camera screen after this many seconds of inactivity. Shows the branded right half of the 4×6 template. Set to 0 to disable.")
                }

                Section {
                    Stepper(
                        settings.returnToCameraSeconds == 0
                            ? "Return to camera: off"
                            : "Return to camera after: \(settings.returnToCameraSeconds)s",
                        value: $settings.returnToCameraSeconds,
                        in: 0...300,
                        step: 15
                    )
                } header: {
                    Text("Post-capture auto-return")
                } footer: {
                    Text("After a fresh capture, the strip detail screen auto-closes back to the camera after this many seconds of inactivity. Sheets (Email, SMS, AirDrop, Print) pause the timer. Gallery browsing is exempt. Set to 0 to disable.")
                }

                Section {
                    LabeledContent("Status") {
                        printStatusLabel
                    }
                    if case let .online(host, port) = printService.state {
                        LabeledContent("Server") { Text("\(host):\(port)").font(.callout.monospaced()) }
                    }
                    if let last = printService.lastHealthAt {
                        LabeledContent("Last health") {
                            Text(last, style: .relative).font(.callout.monospaced())
                        }
                    }
                } header: {
                    Text("Print server")
                } footer: {
                    Text("Discovered over Bonjour (_photoboot-print._tcp). The Print button hides automatically when the server isn't reachable.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private var printStatusLabel: some View {
        switch printService.state {
        case .searching:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Searching…").foregroundStyle(.secondary)
            }
        case .online:
            Label("Online", systemImage: "checkmark.circle.fill")
                .labelStyle(.titleAndIcon)
                .foregroundStyle(.green)
        case .offline(let reason):
            VStack(alignment: .trailing, spacing: 2) {
                Label("Offline", systemImage: "xmark.circle.fill")
                    .foregroundStyle(.red)
                Text(reason)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }
        }
    }
}
