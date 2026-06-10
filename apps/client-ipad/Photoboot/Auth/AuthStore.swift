import Foundation
import Observation
import Supabase

@MainActor
@Observable
final class AuthStore {
    enum State {
        case loading
        case signedOut
        case signedIn(User)
    }

    private(set) var state: State = .loading
    private var observerTask: Task<Void, Never>?

    init() {
        observerTask = Task { [weak self] in
            await self?.observe()
        }
    }

    deinit {
        observerTask?.cancel()
    }

    func signIn(email: String, password: String) async throws {
        _ = try await SupabaseService.shared.client.auth.signIn(
            email: email,
            password: password
        )
    }

    func signOut() async {
        try? await SupabaseService.shared.client.auth.signOut()
    }

    private func observe() async {
        let auth = SupabaseService.shared.client.auth
        for await change in auth.authStateChanges {
            if let user = change.session?.user {
                state = .signedIn(user)
            } else {
                state = .signedOut
            }
        }
    }
}
