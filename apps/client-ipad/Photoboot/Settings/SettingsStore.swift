import Foundation
import Observation

/// Per-device settings persisted in UserDefaults: which strip format prints,
/// how long the first countdown is, how long every subsequent shot's
/// countdown is, whether to show the SMS consent disclosure. Defaults to
/// 4×6 / 3s / 3s / consent ON.
@MainActor
@Observable
final class SettingsStore {
    static let shared = SettingsStore()

    private let defaults = UserDefaults.standard
    private enum Key {
        static let preferredFormat = "photoboot.settings.preferredFormat"
        static let firstCountdown = "photoboot.settings.firstCountdown"
        static let nextCountdown = "photoboot.settings.nextCountdown"
        static let showSmsConsent = "photoboot.settings.showSmsConsent"
        static let splashDelay = "photoboot.settings.splashDelay"
        static let returnToCamera = "photoboot.settings.returnToCamera"
        static let printingEnabled = "photoboot.settings.printingEnabled"
        static let maxPrintCopies = "photoboot.settings.maxPrintCopies"
    }

    var preferredFormat: StripFormat {
        didSet { defaults.set(preferredFormat.rawValue, forKey: Key.preferredFormat) }
    }

    var firstCountdownSeconds: Int {
        didSet { defaults.set(firstCountdownSeconds, forKey: Key.firstCountdown) }
    }

    var nextCountdownSeconds: Int {
        didSet { defaults.set(nextCountdownSeconds, forKey: Key.nextCountdown) }
    }

    var showSmsConsent: Bool {
        didSet { defaults.set(showSmsConsent, forKey: Key.showSmsConsent) }
    }

    /// Seconds of inactivity on the camera screen before the splash takes
    /// over. 0 disables it entirely.
    var splashDelaySeconds: Int {
        didSet { defaults.set(splashDelaySeconds, forKey: Key.splashDelay) }
    }

    /// Seconds of inactivity on the post-capture strip detail screen
    /// before the kiosk auto-returns to the camera. 0 disables it.
    /// Only applies after a fresh capture — gallery browsing is exempt.
    var returnToCameraSeconds: Int {
        didSet { defaults.set(returnToCameraSeconds, forKey: Key.returnToCamera) }
    }

    /// Global kill-switch for the Print button on the strip detail screen.
    /// When false, the button is hidden — useful for events without a
    /// printer attached. When true (the default) the button is always
    /// shown, even if the server or printer is currently unreachable;
    /// failures surface as toasts on submit.
    var printingEnabled: Bool {
        didSet { defaults.set(printingEnabled, forKey: Key.printingEnabled) }
    }

    /// Upper bound on the copies picker shown when the operator taps Print
    /// on a strip. 1 means the picker is skipped and the button prints one
    /// copy directly. Matches the print server's own 1..10 clamp.
    var maxPrintCopies: Int {
        didSet { defaults.set(maxPrintCopies, forKey: Key.maxPrintCopies) }
    }

    private init() {
        if let raw = defaults.string(forKey: Key.preferredFormat),
           let format = StripFormat(rawValue: raw) {
            self.preferredFormat = format
        } else {
            self.preferredFormat = .fourBySix
        }

        let firstStored = defaults.integer(forKey: Key.firstCountdown)
        self.firstCountdownSeconds = firstStored > 0 ? firstStored : 3

        let nextStored = defaults.integer(forKey: Key.nextCountdown)
        self.nextCountdownSeconds = nextStored > 0 ? nextStored : 3

        // UserDefaults returns false if a Bool key has never been set, which
        // would silently flip the default to off on first install. Only honor
        // a stored value if the key was explicitly written.
        if defaults.object(forKey: Key.showSmsConsent) != nil {
            self.showSmsConsent = defaults.bool(forKey: Key.showSmsConsent)
        } else {
            self.showSmsConsent = true
        }

        // 0 = disabled, so distinguish "never set" (default 10) from
        // "explicitly 0" via object(forKey:) rather than relying on the
        // integer-returns-0-for-missing-key behavior.
        if defaults.object(forKey: Key.splashDelay) != nil {
            self.splashDelaySeconds = defaults.integer(forKey: Key.splashDelay)
        } else {
            self.splashDelaySeconds = 60
        }

        if defaults.object(forKey: Key.returnToCamera) != nil {
            self.returnToCameraSeconds = defaults.integer(forKey: Key.returnToCamera)
        } else {
            self.returnToCameraSeconds = 60
        }

        if defaults.object(forKey: Key.printingEnabled) != nil {
            self.printingEnabled = defaults.bool(forKey: Key.printingEnabled)
        } else {
            self.printingEnabled = true
        }

        let maxStored = defaults.integer(forKey: Key.maxPrintCopies)
        self.maxPrintCopies = (1...10).contains(maxStored) ? maxStored : 5
    }
}
