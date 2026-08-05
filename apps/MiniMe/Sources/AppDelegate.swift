import AppKit
import SwiftUI
import Combine

/// AppKit lifecycle for the menu-bar agent.
///
/// Same shape as Upright's: the popover and its SwiftUI content are built
/// lazily and only live while the panel is open, and the status glyph is driven
/// by a single de-duplicated publisher so idle redraws are essentially zero.
final class AppDelegate: NSObject, NSApplicationDelegate {

    private let state = AppState()

    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Belt-and-suspenders: LSUIElement already makes this an agent, but be
        // explicit in case the app is launched oddly.
        NSApp.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = StatusGlyph.ring(progress: Double(state.menuBarStep) / 4)
            button.imagePosition = .imageOnly
            button.action = #selector(togglePopover(_:))
            button.target = self
        }

        state.$menuBarStep
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] step in
                self?.statusItem.button?.image = StatusGlyph.ring(progress: Double(step) / 4)
            }
            .store(in: &cancellables)
    }

    // MARK: Popover

    private func ensurePopover() {
        guard popover == nil else { return }
        let p = NSPopover()
        p.behavior = .transient
        p.animates = false
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
}

extension AppDelegate: NSPopoverDelegate {
    func popoverWillShow(_ notification: Notification) {
        state.popoverIsOpen = true
    }

    func popoverDidClose(_ notification: Notification) {
        state.popoverIsOpen = false
    }
}
