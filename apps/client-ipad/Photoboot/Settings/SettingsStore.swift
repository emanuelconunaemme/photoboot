import Foundation
import Observation

/// Per-device settings persisted in UserDefaults: which strip format prints,
/// how long the first countdown is, how long every subsequent shot's
/// countdown is. Defaults to 4×6 / 3s / 3s.
@MainActor
@Observable
final class SettingsStore {
    static let shared = SettingsStore()

    private let defaults = UserDefaults.standard
    private enum Key {
        static let preferredFormat = "photoboot.settings.preferredFormat"
        static let firstCountdown = "photoboot.settings.firstCountdown"
        static let nextCountdown = "photoboot.settings.nextCountdown"
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
    }
}
