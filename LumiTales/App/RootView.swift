import SwiftUI

/// Top-level tabs. Each tab's content receives `tabIsActive` through the environment so that
/// character renderers (and the twinkling background) pause while their tab is hidden.
struct RootView: View {
    enum AppTab: Hashable {
        case showcase
        case stories
    }

    @State private var selection: AppTab = .showcase

    var body: some View {
        TabView(selection: $selection) {
            ShowcaseView()
                .environment(\.tabIsActive, selection == .showcase)
                .tabItem {
                    Label(L10n.charactersTab, systemImage: "sparkles")
                }
                .tag(AppTab.showcase)

            StoryView()
                .environment(\.tabIsActive, selection == .stories)
                .tabItem {
                    Label(L10n.storiesTab, systemImage: "book.closed")
                }
                .tag(AppTab.stories)
        }
        .tint(AppTheme.accent)
    }
}
