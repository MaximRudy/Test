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
            Tab(L10n.charactersTab, systemImage: "sparkles", value: AppTab.showcase) {
                ShowcaseView()
                    .environment(\.tabIsActive, selection == .showcase)
            }

            Tab(L10n.storiesTab, systemImage: "book.closed", value: AppTab.stories) {
                StoryView()
                    .environment(\.tabIsActive, selection == .stories)
            }
        }
        .tint(AppTheme.accent)
    }
}
