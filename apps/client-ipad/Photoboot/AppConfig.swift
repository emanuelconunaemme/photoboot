import Foundation

enum AppConfig {
    // Local dev defaults. Override SUPABASE_URL / SUPABASE_ANON_KEY in the scheme's
    // environment variables when you need to point at the cloud project.
    //
    // After `pnpm supabase start`, copy the "API URL" and "anon key" lines into
    // these defaults — they regenerate per project.
    static let supabaseURL: URL = {
        if let env = ProcessInfo.processInfo.environment["SUPABASE_URL"],
           let url = URL(string: env) {
            return url
        }
        return URL(string: "http://127.0.0.1:54321")!
    }()

    static let supabaseAnonKey: String = {
        if let env = ProcessInfo.processInfo.environment["SUPABASE_ANON_KEY"],
           !env.isEmpty {
            return env
        }
        // Local Supabase publishable key (acts as the anon key for client apps).
        // Regenerates per CLI version — refresh from `pnpm supabase status` if it stops working.
        return "sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH"
    }()
}
