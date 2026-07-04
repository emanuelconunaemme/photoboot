import SwiftUI

struct SettingsView: View {
    /// Event being operated on, used to surface the per-event primary
    /// and secondary colors as shortcut chips on the ring light picker.
    /// Optional so the sheet can also be presented from contexts where
    /// no event is active (none exist today, but it costs nothing to be
    /// defensive).
    var event: Event?
    /// Called when the "Refresh event data" button pulls a fresh row from
    /// Supabase. The parent uses this to update the event it's holding so
    /// downstream views re-render with the new templates/colors.
    var onEventRefreshed: ((Event) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var settings = SettingsStore.shared
    @State private var printService = PrintService.shared
    @State private var ringLight = RingLightController.shared
    @State private var remote = CameraRemoteController.shared
    @State private var pickedColor: Color = .white
    @State private var colorDebounce: Task<Void, Never>?
    @State private var isRefreshingEvent = false
    @State private var refreshMessage: String?

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
                    Toggle("Enable printing", isOn: $settings.printingEnabled)
                    Stepper(
                        "Max copies per print: \(settings.maxPrintCopies)",
                        value: $settings.maxPrintCopies,
                        in: 1...10
                    )
                } header: {
                    Text("Printing")
                } footer: {
                    Text("When printing is off, the Print button is hidden on the strip detail screen. Max copies is the largest number the guest can pick when tapping Print (1 skips the picker and prints one copy directly).")
                }

                Section {
                    LabeledContent("Server") { serverStatusLabel }
                    LabeledContent("Printer") { printerStatusLabel }
                    if let last = printService.lastHealthAt {
                        LabeledContent("Last health") {
                            Text(last, style: .relative).font(.callout.monospaced())
                        }
                    }
                } header: {
                    Text("Print server status")
                } footer: {
                    Text("Discovered over Bonjour (_photoboot-print._tcp). 'Server' is whether the iPad can reach the print server; 'Printer' is whether the printer itself is ready to take a job.")
                }

                eventDataSection
                ringLightSection
                cameraRemoteSection
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                pickedColor = Color(hex: ringLight.colorHex)
                // Silently reconnect to a previously-paired ring light
                // so the section opens already "Connected". First-time
                // pairing still requires an explicit Scan tap so we
                // don't trigger the BLE permission prompt for users
                // who never plan to use the light.
                if ringLight.hasSavedPeripheral,
                   !ringLight.state.isConnected,
                   !ringLight.state.isBusy {
                    ringLight.scan()
                }
            }
        }
    }

    @ViewBuilder
    private var serverStatusLabel: some View {
        switch printService.serverState {
        case .searching:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Searching…").foregroundStyle(.secondary)
            }
        case .reachable(let host, let port):
            VStack(alignment: .trailing, spacing: 2) {
                Label("Online", systemImage: "checkmark.circle.fill")
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(.green)
                Text("\(host):\(port)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }
        case .unreachable(let reason):
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

    @ViewBuilder
    private var cameraRemoteSection: some View {
        Section {
            Toggle("Use volume button as shutter", isOn: Binding(
                get: { remote.isEnabled },
                set: { remote.isEnabled = $0 }
            ))
            LabeledContent("Status") {
                Text(remote.state.summary)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }
            Button {
                openBluetoothSettings()
            } label: {
                Label("Pair in iOS Settings…", systemImage: "arrow.up.right.square")
            }
        } header: {
            Text("Camera remote")
        } footer: {
            Text("The clicker that ships with the photo booth stand sends a Volume Up press over Bluetooth. Pair it once in iOS Settings → Bluetooth (look for an entry like “AB Shutter” or “BL-100”). When this is on, pressing the clicker — or either iPad volume button — on the camera screen starts the same countdown as tapping the on-screen capture button. Volume buttons keep their normal behavior everywhere else in the app.")
        }
    }

    private func openBluetoothSettings() {
        // Try the unofficial deep link to the Bluetooth pane first;
        // fall back to the app's own Settings page if iOS refuses it.
        let direct = URL(string: "App-Prefs:root=Bluetooth")!
        UIApplication.shared.open(direct) { ok in
            guard !ok, let fallback = URL(string: UIApplication.openSettingsURLString) else { return }
            UIApplication.shared.open(fallback)
        }
    }

    @ViewBuilder
    private var eventDataSection: some View {
        if let event {
            Section {
                Button {
                    Task { await refreshEvent(event) }
                } label: {
                    HStack(spacing: 8) {
                        if isRefreshingEvent {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                        Text(isRefreshingEvent ? "Refreshing…" : "Refresh event data")
                    }
                }
                .disabled(isRefreshingEvent)
                if let refreshMessage {
                    Text(refreshMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Event data")
            } footer: {
                Text("Re-pulls the event row from Supabase and re-downloads its background templates. Use this after editing the event or re-uploading templates from the admin so the iPad picks up the changes without a restart.")
            }
        }
    }

    private func refreshEvent(_ current: Event) async {
        isRefreshingEvent = true
        refreshMessage = nil
        defer { isRefreshingEvent = false }
        do {
            guard let fresh = try await EventsStore.refetch(id: current.id) else {
                refreshMessage = "Event not found."
                return
            }
            await BackgroundCache.shared.refresh(for: fresh)
            onEventRefreshed?(fresh)
            refreshMessage = "Templates refreshed."
        } catch {
            refreshMessage = "Refresh failed: \(error.localizedDescription)"
        }
    }

    @ViewBuilder
    private var ringLightSection: some View {
        Section {
            if ringLight.state.isConnected {
                LabeledContent("Status") {
                    Label(ringLight.state.summary, systemImage: "checkmark.circle.fill")
                        .labelStyle(.titleAndIcon)
                        .foregroundStyle(.green)
                }
                Toggle("Light on", isOn: Binding(
                    get: { ringLight.isOn },
                    set: { ringLight.setOn($0) }
                ))
                VStack(alignment: .leading, spacing: 6) {
                    Text("Brightness: \(ringLight.brightness)%")
                    Slider(
                        value: Binding(
                            get: { Double(ringLight.brightness) },
                            set: { ringLight.setBrightness(Int($0)) }
                        ),
                        in: 0...100,
                        step: 5
                    )
                }
                ringLightColorRow
                Button("Disconnect", role: .destructive) {
                    ringLight.disconnect()
                }
            } else {
                LabeledContent("Status") {
                    ringLightStatusLabel
                }
                Button {
                    ringLight.scan()
                } label: {
                    HStack(spacing: 8) {
                        if ringLight.state.isBusy {
                            ProgressView().controlSize(.small)
                        }
                        Text(ringLightScanButtonTitle)
                    }
                }
                .disabled(ringLight.state.isBusy)
            }
        } header: {
            Text("Ring light")
        } footer: {
            Text("Bluetooth ring light in the photo booth stand (ELK-BLEDOM). Pair once — the iPad remembers it and reconnects automatically next time you open Settings.")
        }
    }

    @ViewBuilder
    private var ringLightStatusLabel: some View {
        switch ringLight.state {
        case .scanning, .connecting:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text(ringLight.state.summary).foregroundStyle(.secondary)
            }
        case .poweredOff, .unauthorized, .failed:
            Label(ringLight.state.summary, systemImage: "exclamationmark.triangle.fill")
                .labelStyle(.titleAndIcon)
                .foregroundStyle(.orange)
                .multilineTextAlignment(.trailing)
        default:
            Text(ringLight.state.summary).foregroundStyle(.secondary)
        }
    }

    private var ringLightScanButtonTitle: String {
        switch ringLight.state {
        case .scanning:                return "Scanning…"
        case .connecting:              return "Connecting…"
        case .noneFound, .failed:      return "Try again"
        case .disconnected:            return ringLight.hasSavedPeripheral ? "Reconnect" : "Scan for ring light"
        default:                       return "Scan for ring light"
        }
    }

    @ViewBuilder
    private var ringLightColorRow: some View {
        HStack(spacing: 12) {
            Text("Color")
            Spacer()
            if let event {
                ringLightColorChip(hex: event.primaryColor, label: "Primary")
                ringLightColorChip(hex: event.secondaryColor, label: "Secondary")
            }
            ColorPicker("Color", selection: $pickedColor, supportsOpacity: false)
                .labelsHidden()
                .onChange(of: pickedColor) { _, new in
                    let hex = new.hexString
                    guard hex != ringLight.colorHex else { return }
                    // Throttle: ColorPicker fires onChange for every
                    // drag tick. Coalesce to one BLE write per ~80ms so
                    // the link doesn't fill up while the user is
                    // sliding around.
                    colorDebounce?.cancel()
                    colorDebounce = Task {
                        try? await Task.sleep(for: .milliseconds(80))
                        if Task.isCancelled { return }
                        ringLight.setColor(hex: hex)
                    }
                }
        }
    }

    private func ringLightColorChip(hex: String, label: String) -> some View {
        Button {
            ringLight.setColor(hex: hex)
            pickedColor = Color(hex: hex)
        } label: {
            VStack(spacing: 4) {
                Circle()
                    .fill(Color(hex: hex))
                    .frame(width: 32, height: 32)
                    .overlay(Circle().stroke(.secondary.opacity(0.35), lineWidth: 1))
                Text(label).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var printerStatusLabel: some View {
        switch printService.printerState {
        case .unknown:
            Text("—").foregroundStyle(.secondary)
        case .ready:
            Label("Ready", systemImage: "checkmark.circle.fill")
                .labelStyle(.titleAndIcon)
                .foregroundStyle(.green)
        case .notReady(let reason):
            VStack(alignment: .trailing, spacing: 2) {
                Label("Not ready", systemImage: "exclamationmark.triangle.fill")
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(.orange)
                Text(reason)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }
        }
    }
}
