import SwiftUI

@main
struct PhotobootApp: App {
    @State private var auth = AuthStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(auth)
                .preferredColorScheme(.light)
        }
    }
}

private struct RootView: View {
    @Environment(AuthStore.self) private var auth

    var body: some View {
        switch auth.state {
        case .loading:
            ProgressView().controlSize(.large)
        case .signedOut:
            LoginView()
        case .signedIn:
            SignedInRoot()
        }
    }
}

private struct SignedInRoot: View {
    @State private var currentEvent: Event?
    @State private var autoOpenCapture = false
    @State private var isResolving = true

    var body: some View {
        Group {
            if isResolving {
                ProgressView().controlSize(.large)
            } else if let currentEvent {
                NavigationStack {
                    EventHomeView(
                        event: currentEvent,
                        autoOpenCapture: autoOpenCapture
                    ) {
                        EventsStore.clearRemembered()
                        autoOpenCapture = false
                        self.currentEvent = nil
                    }
                }
                .id(currentEvent.id)
            } else {
                NavigationStack {
                    EventPickerView { event in
                        // User explicitly picked an event — show event home,
                        // not the camera. Auto-open only happens when the
                        // last-used event is resolved automatically on launch.
                        autoOpenCapture = false
                        currentEvent = event
                    }
                }
            }
        }
        .task {
            if let resolved = await EventsStore.resolveLastSelected() {
                autoOpenCapture = true
                currentEvent = resolved
            }
            isResolving = false
        }
    }
}
