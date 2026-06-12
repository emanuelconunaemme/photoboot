import Foundation

enum AppConfig {
    // Defaults point at the cloud project. Override SUPABASE_URL / SUPABASE_ANON_KEY
    // in the Xcode scheme's environment variables to point at a local stack instead
    // (e.g. http://127.0.0.1:54321 with the key from `make status`).
    static let supabaseURL: URL = {
        if let env = ProcessInfo.processInfo.environment["SUPABASE_URL"],
           let url = URL(string: env) {
            return url
        }
        return URL(string: "https://fyhddmerdksdbdryvtaf.supabase.co")!
    }()

    static let supabaseAnonKey: String = {
        if let env = ProcessInfo.processInfo.environment["SUPABASE_ANON_KEY"],
           !env.isEmpty {
            return env
        }
        return "sb_publishable_zjz_2Uc3TG7wjA9JOPFEkA_suHDteZo"
    }()
}
