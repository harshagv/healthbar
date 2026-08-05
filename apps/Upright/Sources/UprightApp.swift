import SwiftUI

/// Menu-bar agent entry point.
///
/// The UI lives entirely in an AppKit `NSStatusItem` managed by `AppDelegate`
/// (see that file). We keep a SwiftUI `App` only as the launch shell so the
/// `@NSApplicationDelegateAdaptor` is installed; the `Settings` scene produces
/// no visible window for an `LSUIElement` agent.
@main
struct UprightApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}
