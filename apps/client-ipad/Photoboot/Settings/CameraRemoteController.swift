import AVFoundation
import Foundation
import MediaPlayer
import Observation
import UIKit
import os

/// Detects presses of the iPad's volume buttons — including the
/// Volume Up that the photo-booth-stand BLE clicker (an "AB Shutter"
/// in iOS mode) sends — and broadcasts them to subscribers.
///
/// Why volume KVO instead of GCKeyboard: those clickers emit
/// consumer-control HID events (Volume Up), not the standard
/// keyboard-page keys that GameController exposes. The reliable
/// public-API way to catch them in a third-party app is to observe
/// `AVAudioSession.outputVolume` and use a hidden `MPVolumeView` to
/// keep the system volume parked in the middle so each press
/// produces a fresh KVO event (max volume → no further increases).
///
/// Active only while a subscriber is attached AND the toggle is on,
/// so volume buttons keep their normal behavior everywhere outside
/// the capture screen.
@MainActor
@Observable
final class CameraRemoteController {
    static let shared = CameraRemoteController()

    enum State: Equatable {
        case off                       // disabled in Settings
        case standby                   // enabled, but no subscriber on screen
        case listening                 // enabled, subscribed, actively armed
        case unavailable(reason: String)

        var summary: String {
            switch self {
            case .off:                 return "Off"
            case .standby:             return "Active on the camera screen"
            case .listening:           return "Listening"
            case .unavailable(let r):  return r
            }
        }
    }

    private(set) var state: State = .off

    /// User-facing on/off switch. Persisted; defaults to on.
    var isEnabled: Bool {
        didSet {
            defaults.set(isEnabled, forKey: Key.enabled)
            reevaluate()
        }
    }

    private let log = Logger(subsystem: "com.mazzillie.photoboot", category: "camera-remote")
    private let defaults = UserDefaults.standard
    private enum Key { static let enabled = "photoboot.remote.enabled" }

    private var triggers: [UUID: () -> Void] = [:]
    private var volumeObservation: NSKeyValueObservation?
    private var hiddenVolumeView: MPVolumeView?
    private var volumeSlider: UISlider?
    private var ignoreNextVolumeChange = false
    private var lastTriggerAt: Date = .distantPast
    private var seedTask: Task<Void, Never>?
    private static let dedupeWindow: TimeInterval = 0.35
    private static let parkedVolume: Float = 0.5

    private init() {
        if defaults.object(forKey: Key.enabled) != nil {
            isEnabled = defaults.bool(forKey: Key.enabled)
        } else {
            isEnabled = true
        }
        updateState()
    }

    // MARK: - Subscriber API

    /// Subscribe to volume-button presses. The controller activates on
    /// the first subscription and tears down when the last subscriber
    /// leaves, so the rest of the app keeps normal volume behavior.
    @discardableResult
    func addTrigger(_ handler: @escaping () -> Void) -> UUID {
        let id = UUID()
        triggers[id] = handler
        reevaluate()
        return id
    }

    func removeTrigger(_ id: UUID) {
        triggers.removeValue(forKey: id)
        reevaluate()
    }

    // MARK: - Activation

    private func reevaluate() {
        let want = isEnabled && !triggers.isEmpty
        switch (want, volumeObservation != nil) {
        case (true, false):  activate()
        case (false, true):  deactivate()
        default:             updateState()
        }
    }

    private func updateState() {
        if case .unavailable = state { return }
        if !isEnabled {
            state = .off
        } else if triggers.isEmpty {
            state = .standby
        } else if volumeObservation != nil {
            state = .listening
        } else {
            state = .standby
        }
    }

    private func activate() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            log.warning("audio session activation failed: \(error.localizedDescription, privacy: .public)")
            state = .unavailable(reason: "Couldn't open the audio session")
            return
        }
        installVolumeView()
        volumeObservation = session.observe(\.outputVolume, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in self?.handleVolumeChange() }
        }
        state = .listening
        log.info("listening for volume-button presses")
    }

    private func deactivate() {
        volumeObservation?.invalidate()
        volumeObservation = nil
        seedTask?.cancel()
        seedTask = nil
        removeVolumeView()
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        // Don't overwrite a sticky .unavailable; otherwise reflect
        // current toggle/subscriber state.
        if case .unavailable = state { return }
        updateState()
    }

    // MARK: - MPVolumeView plumbing

    private func installVolumeView() {
        guard hiddenVolumeView == nil else { return }
        guard let window = Self.keyWindow else {
            log.warning("no window available for MPVolumeView; volume HUD may show")
            return
        }
        let v = MPVolumeView(frame: CGRect(x: -2000, y: -2000, width: 1, height: 1))
        v.alpha = 0.001
        v.showsVolumeSlider = true
        v.isUserInteractionEnabled = false
        window.addSubview(v)
        hiddenVolumeView = v
        // The internal slider isn't synchronously available — wait one
        // run-loop tick before grabbing it and parking the volume.
        seedTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(60))
            guard let self, !Task.isCancelled else { return }
            self.volumeSlider = v.subviews.compactMap { $0 as? UISlider }.first
            self.parkVolume()
        }
    }

    private func removeVolumeView() {
        hiddenVolumeView?.removeFromSuperview()
        hiddenVolumeView = nil
        volumeSlider = nil
    }

    /// Push the system volume back to mid-range so the very next press
    /// of Volume Up (or Down) produces a fresh KVO event. Flags the
    /// next change as one we should swallow.
    private func parkVolume() {
        guard let slider = volumeSlider else { return }
        let current = AVAudioSession.sharedInstance().outputVolume
        if abs(current - Self.parkedVolume) < 0.01 { return }
        ignoreNextVolumeChange = true
        slider.setValue(Self.parkedVolume, animated: false)
    }

    private func handleVolumeChange() {
        if ignoreNextVolumeChange {
            ignoreNextVolumeChange = false
            return
        }
        let now = Date()
        guard now.timeIntervalSince(lastTriggerAt) > Self.dedupeWindow else { return }
        lastTriggerAt = now
        log.info("volume-button press → trigger")
        for handler in triggers.values { handler() }
        // Re-park the volume after a short delay so a second KVO that
        // iOS sometimes emits right after the press doesn't bounce
        // back into us. Cancellable in case we deactivate first.
        seedTask?.cancel()
        seedTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(80))
            guard let self, !Task.isCancelled else { return }
            self.parkVolume()
        }
    }

    private static var keyWindow: UIWindow? {
        for scene in UIApplication.shared.connectedScenes {
            guard let ws = scene as? UIWindowScene else { continue }
            if let key = ws.windows.first(where: \.isKeyWindow) { return key }
        }
        return UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.windows.first }
            .first
    }
}
