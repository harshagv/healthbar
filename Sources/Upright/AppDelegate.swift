import AppKit
import SwiftUI
import Combine

/// AppKit lifecycle for the menu-bar agent.
///
/// Owns the `NSStatusItem` (the menu-bar icon) and an `NSPopover` that hosts the
/// SwiftUI panel. The popover is built lazily and its SwiftUI content is only
/// alive while it's open, so the (relatively expensive) Charts-based UI does no
/// work when the user isn't looking at it. The status-item glyph is driven by a
/// single dedicated publisher rather than the per-sample motion stream, keeping
/// idle redraws to essentially zero.
final class AppDelegate: NSObject, NSApplicationDelegate {

    private let state = AppState()

    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Belt-and-suspenders: the app is an LSUIElement agent, but ensure no
        // Dock icon / menu bar even if launched oddly.
        NSApp.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = symbolImage(state.menuBarSymbol)
            button.imagePosition = .imageOnly
            button.action = #selector(togglePopover(_:))
            button.target = self
        }

        // Update the glyph only when the *symbol name* actually changes — not on
        // every sensor sample.
        state.$menuBarSymbolName
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] name in
                self?.statusItem.button?.image = self?.symbolImage(name)
            }
            .store(in: &cancellables)
    }

    func applicationWillTerminate(_ notification: Notification) {
        state.flushSessionToHistory()
    }

    // MARK: Popover

    /// Build the popover (and its SwiftUI hosting controller) on first use.
    private func ensurePopover() {
        guard popover == nil else { return }
        let p = NSPopover()
        p.behavior = .transient                 // closes when focus is lost
        p.animates = false                       // cheaper open/close
        p.contentViewController = NSHostingController(rootView: MenuContentView(state: state))
        p.delegate = self
        popover = p
    }

    @objc private func togglePopover(_ sender: Any?) {
        ensurePopover()
        if popover.isShown {
            popover.performClose(sender)
        } else if let button = statusItem.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func symbolImage(_ name: String) -> NSImage? {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "Upright")
        image?.isTemplate = true                 // adopt menu-bar tint automatically
        return image
    }
}

extension AppDelegate: NSPopoverDelegate {
    func popoverWillShow(_ notification: Notification) {
        state.popoverIsOpen = true
    }

    func popoverDidClose(_ notification: Notification) {
        state.popoverIsOpen = false
    }
}
