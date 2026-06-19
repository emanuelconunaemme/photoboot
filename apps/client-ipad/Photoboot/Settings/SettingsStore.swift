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
    }
}
