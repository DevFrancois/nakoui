import SwiftUI

enum SidebarRoute: String, Hashable, CaseIterable {
    case video
    case bookmarks
    case communities
    case messages
    case lists
    case spaces
    case settings
    case helpCenter

    var title: String {
        switch self {
        case .video: "Video"
        case .bookmarks: "Bookmarks"
        case .communities: "Communities"
        case .messages: "Messages"
        case .lists: "Lists"
        case .spaces: "Spaces"
        case .settings: "Settings"
        case .helpCenter: "Help Center"
        }
    }

    var symbol: String {
        switch self {
        case .video: "video"
        case .bookmarks: "bookmark"
        case .communities: "person.2"
        case .messages: "bubble"
        case .lists: "list.clipboard"
        case .spaces: "mic"
        case .settings: "gearshape"
        case .helpCenter: "questionmark.circle"
        }
    }

    var accessibilityID: String {
        "sidebar.\(rawValue)"
    }
}

struct SideBar: View {
    let onSelect: (SidebarRoute) -> Void

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 0) {
                profileHeader
                    .padding(.bottom, 15)

                Divider()
                    .background(.white.tertiary)
                    .padding(.horizontal, -15)

                VStack(alignment: .leading, spacing: 14) {
                    ForEach(SidebarRoute.allCases, id: \.self) { route in
                        if route == .settings {
                            Divider()
                                .background(.white.tertiary)
                                .padding(.vertical, 8)
                        }

                        routeButton(route)
                    }
                }
                .padding(.top, 10)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(15)
        }
        .accessibilityIdentifier("sidebar.menu")
    }

    private var profileHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Circle()
                .fill(.fill)
                .frame(width: 60, height: 60)
                .padding(.bottom, 10)
                .accessibilityHidden(true)

            Text("iJustine")
                .font(.title3)
                .fontWeight(.semibold)
                .accessibilityAddTraits(.isHeader)

            Text("@iJustine")
                .foregroundStyle(.gray)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    followingCount
                    followerCount
                }
                .fixedSize(horizontal: true, vertical: false)

                VStack(alignment: .leading, spacing: 4) {
                    followingCount
                    followerCount
                }
            }
            .font(.callout)
            .fontWeight(.medium)
            .padding(.top, 5)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var followingCount: some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text("3K")
                .fontWeight(.bold)
            Text("Following")
                .foregroundStyle(.primary.opacity(0.7))
        }
        .accessibilityElement(children: .combine)
    }

    private var followerCount: some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text("1.7M")
                .fontWeight(.bold)
            Text("Followers")
                .foregroundStyle(.primary.opacity(0.7))
        }
        .accessibilityElement(children: .combine)
    }

    private func routeButton(_ route: SidebarRoute) -> some View {
        Button {
            onSelect(route)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: route.symbol)
                    .font(.title3)
                    .frame(width: 30)
                    .symbolVariant(.fill)
                    .accessibilityHidden(true)

                Text(route.title)
                    .font(.title3)
                    .fontWeight(.bold)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(Color.primary)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(route.accessibilityID)
    }
}
