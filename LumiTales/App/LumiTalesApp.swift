import SwiftUI

/// LumiTales — a fairy-tale narrator built on the StoryCharacters engine.
/// The app is dark-only: the night-sky gradients and Liquid Glass panels are designed for it.
@main
struct LumiTalesApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
        }
    }
}
