import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var settings = SettingsStore.shared

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
}
