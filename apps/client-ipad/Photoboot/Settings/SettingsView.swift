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
