import SwiftUI

struct EventHomeView: View {
    let event: Event
    let onChangeEvent: () -> Void

    @Environment(AuthStore.self) private var auth
    @State private var route: Route?

    enum Route: Hashable {
        case capture
        case gallery
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 36) {
                header

                VStack(spacing: 18) {
                    HomeActionCard(
                        title: "Take a picture",
                        subtitle: "Smile! Tap to start the countdown.",
                        systemImage: "camera.fill",
                        style: .gradient,
                        action: { route = .capture }
                    )

                    HomeActionCard(
                        title: "See pictures",
                        subtitle: "Browse the gallery for this event.",
                        systemImage: "photo.on.rectangle.angled",
                        style: .outlined,
                        action: { route = .gallery }
                    )
                }
                .padding(.horizontal, 24)

                Spacer(minLength: 24)
            }
            .padding(.top, 40)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(event.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Change event", systemImage: "arrow.triangle.swap", action: onChangeEvent)
                    Button("Sign out", systemImage: "rectangle.portrait.and.arrow.right") {
                        Task { await auth.signOut() }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                        .foregroundStyle(Brand.pink)
                }
            }
        }
        .navigationDestination(item: $route) { route in
            switch route {
            case .capture: CaptureFlowView(event: event)
            case .gallery: GalleryView(event: event)
            }
        }
    }

    private var header: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Brand.gradient)
                    .frame(width: 96, height: 96)
                    .shadow(color: Brand.pink.opacity(0.4), radius: 18, y: 8)
                Image(systemName: "sparkles")
                    .font(.system(size: 44, weight: .bold))
                    .foregroundStyle(.white)
            }
            Text(event.name)
                .font(.largeTitle.weight(.bold))
                .multilineTextAlignment(.center)
                .foregroundStyle(Brand.gradient)
                .padding(.horizontal, 24)
            Text("What would you like to do?")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
    }
}

private struct HomeActionCard: View {
    enum Style { case gradient, outlined }

    let title: String
    let subtitle: String
    let systemImage: String
    let style: Style
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 18) {
                iconBadge
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(titleColor)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(subtitleColor)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(chevronColor)
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(background)
            .overlay(border)
            .clipShape(.rect(cornerRadius: 24))
            .shadow(color: .black.opacity(0.07), radius: 14, y: 6)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var iconBadge: some View {
        ZStack {
            Circle()
                .fill(style == .gradient ? AnyShapeStyle(Color.white.opacity(0.25)) : AnyShapeStyle(Brand.gradient))
                .frame(width: 60, height: 60)
            Image(systemName: systemImage)
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(.white)
        }
    }

    @ViewBuilder
    private var background: some View {
        switch style {
        case .gradient: Brand.gradient
        case .outlined: Color(.systemBackground)
        }
    }

    @ViewBuilder
    private var border: some View {
        if style == .outlined {
            RoundedRectangle(cornerRadius: 24)
                .stroke(Brand.gradient, lineWidth: 2)
        }
    }

    private var titleColor: Color { style == .gradient ? .white : .primary }
    private var subtitleColor: Color { style == .gradient ? .white.opacity(0.85) : .secondary }
    private var chevronColor: Color { style == .gradient ? .white : Brand.pink }
}
