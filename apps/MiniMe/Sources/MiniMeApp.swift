import SwiftUI

/// MiniMe runs as an `LSUIElement` agent — no Dock icon, no windows of its own.
/// Everything lives in `AppDelegate`; the empty `Settings` scene exists only
/// because SwiftUI's `App` protocol requires at least one scene.
@main
struct MiniMeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}
