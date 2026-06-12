import SwiftUI

struct GalleryView: View {
    let event: Event

    @State private var store = GalleryStore()
    @State private var selected: Strip?

    private let columns = [GridItem(.adaptive(minimum: 160), spacing: 14)]

    var body: some View {
        content
            .navigationTitle("Strips")
            .navigationBarTitleDisplayMode(.inline)
            .background(Color(.systemGroupedBackground))
            .task { await store.load(for: event) }
            .refreshable { await store.load(for: event) }
            .navigationDestination(item: $selected) { strip in
                StripDetailView(strip: strip) { deleted in
                    store.remove(deleted)
                    selected = nil
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        if store.isLoading && store.strips.isEmpty {
            ProgressView().controlSize(.large)
        } else if let error = store.loadError {
            ContentUnavailableView(
                "Couldn't load strips",
                systemImage: "exclamationmark.triangle",
                description: Text(error)
            )
        } else if store.strips.isEmpty {
            ContentUnavailableView(
                "No strips yet",
                systemImage: "photo.on.rectangle.angled",
                description: Text("Take a photo strip and it'll appear here.")
            )
        } else {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(store.strips) { strip in
                        Button { selected = strip } label: {
                            StripThumbnail(strip: strip)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(18)
            }
        }
    }
}

private struct StripThumbnail: View {
    let strip: Strip
    @State private var url: URL?

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .empty:
                placeholder
            case .success(let image):
                image.resizable().scaledToFill()
            case .failure:
                placeholder.overlay(
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                )
            @unknown default:
                placeholder
            }
        }
        .aspectRatio(3.0 / 5.0, contentMode: .fill)
        .frame(maxWidth: .infinity)
        .clipShape(.rect(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Brand.gradient, lineWidth: 2)
        )
        .shadow(color: .black.opacity(0.06), radius: 8, y: 3)
        .task {
            url = try? await StripService.shared.signedURL(for: strip)
        }
    }

    private var placeholder: some View {
        Rectangle().fill(Color(.systemGray5))
    }
}
