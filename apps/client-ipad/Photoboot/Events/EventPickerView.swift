import SwiftUI

struct EventPickerView: View {
    let onSelect: (Event) -> Void

    @Environment(AuthStore.self) private var auth
    @State private var store = EventsStore()

    var body: some View {
        content
            .navigationTitle("Choose event")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Sign out") {
                        Task { await auth.signOut() }
                    }
                }
            }
            .task { await store.load() }
    }

    @ViewBuilder
    private var content: some View {
        if store.isLoading && store.events.isEmpty {
            ProgressView().controlSize(.large)
        } else if let error = store.loadError {
            ContentUnavailableView {
                Label("Couldn't load events", systemImage: "exclamationmark.triangle")
            } description: {
                Text(error)
            } actions: {
                Button(action: { Task { await store.load() } }) {
                    Label("Retry", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent)
                .tint(Brand.pink)
            }
        } else if store.events.isEmpty {
            ContentUnavailableView {
                Label("No events yet", systemImage: "calendar.badge.plus")
            } description: {
                Text("Create one in the admin web app, then refresh.")
            } actions: {
                Button(action: { Task { await store.load() } }) {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent)
                .tint(Brand.pink)
            }
        } else {
            List(store.events) { event in
                Button {
                    store.rememberSelected(event)
                    onSelect(event)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(event.name).font(.headline)
                            Text("\(event.slug) · \(event.status)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
            .refreshable { await store.load() }
        }
    }
}
