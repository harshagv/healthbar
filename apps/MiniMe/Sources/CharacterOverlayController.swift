import AppKit
import SwiftUI

/// Owns the floating panel MiniMe lives in: walks him in from off the right
/// edge, holds him at the bottom-right while he says his piece, then walks him
/// back out.
///
/// The panel is a `.nonactivatingPanel` so clicking a button never steals focus
/// from whatever you're working in, and it sits at `.statusBar` level with
/// `.canJoinAllSpaces` + `.fullScreenAuxiliary` so it shows above other apps
/// and follows you between Spaces.
///
/// Mouse events are ignored entirely except while the bubble is up — an idle
/// character must never come between the user and the window underneath.
final class CharacterOverlayController {

    private enum Phase { case hidden, walkingIn, speaking, walkingOut }

    // Taller than the character needs so a two-line bubble has headroom above
    // his head. He is pinned to the bottom of the panel, so extra height only
    // ever adds room upward — it can never push him down.
    private let panelSize = NSSize(width: 560, height: 430)
    private let walkDuration: TimeInterval = 1.3
    private let edgeInset: CGFloat = 24

    private var panel: NSPanel?
    private var hosting: NSHostingView<CharacterOverlayView>?
    private var phase: Phase = .hidden

    private var walkTimer: Timer?
    private var timeoutTimer: Timer?

    private var message = ""
    private var actions: [CharacterAction] = []
    private var onTimeout: (() -> Void)?

    private let sprites = SpriteLibrary.shared

    // MARK: Public

    /// Walk MiniMe in and show a line. `timeout` dismisses him quietly if the
    /// user never answers — an ignored nudge is a miss, not a nag loop.
    func present(message: String,
                 actions: [CharacterAction],
                 timeout: TimeInterval? = 30,
                 onTimeout: (() -> Void)? = nil) {
        guard sprites.isLoaded else { return }

        self.message = message
        self.actions = actions
        self.onTimeout = onTimeout

        timeoutTimer?.invalidate()
        walkTimer?.invalidate()

        let panel = ensurePanel()
        guard let screen = targetScreen() else { return }

        let targetOrigin = restingOrigin(on: screen)

        // Already on screen? Just swap the line rather than re-running the walk.
        if phase == .speaking {
            render(frames: standingFrames, facingLeft: true, loops: false, bubble: true)
            scheduleTimeout(timeout)
            return
        }

        let startOrigin = NSPoint(x: screen.frame.maxX + 40, y: targetOrigin.y)
        panel.setFrameOrigin(startOrigin)
        panel.ignoresMouseEvents = true
        panel.orderFrontRegardless()

        phase = .walkingIn
        render(frames: sprites.walk, facingLeft: true, loops: true, bubble: false)

        animate(from: startOrigin.x, to: targetOrigin.x) { [weak self] in
            guard let self else { return }
            self.phase = .speaking
            self.panel?.ignoresMouseEvents = false
            self.render(frames: self.standingFrames, facingLeft: true, loops: false, bubble: true)
            self.scheduleTimeout(timeout)
        }
    }

    /// Hand in the air, on a loop — MiniMe taking a victory lap. No buttons:
    /// there's nothing to answer, so it plays out and leaves on its own.
    func celebrate(message: String, duration: TimeInterval = 3.5) {
        guard phase == .speaking || phase == .walkingIn else { return }
        timeoutTimer?.invalidate()

        self.message = message
        self.actions = []
        panel?.ignoresMouseEvents = true
        phase = .speaking
        render(frames: standingFrames, facingLeft: true, loops: true, bubble: true, celebrating: true)

        timeoutTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            self?.dismiss()
        }
    }

    /// Walk him back out to the right and close.
    func dismiss() {
        timeoutTimer?.invalidate()
        walkTimer?.invalidate()
        guard let panel, phase != .hidden, phase != .walkingOut else {
            hide()
            return
        }

        phase = .walkingOut
        panel.ignoresMouseEvents = true
        render(frames: sprites.walk, facingLeft: false, loops: true, bubble: false)

        let offscreen = (targetScreen()?.frame.maxX ?? panel.frame.maxX) + 40
        animate(from: panel.frame.origin.x, to: offscreen) { [weak self] in
            self?.hide()
        }
    }

    var isVisible: Bool { phase != .hidden }

    // MARK: Panel

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }

        let p = NSPanel(contentRect: NSRect(origin: .zero, size: panelSize),
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered,
                        defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.level = .statusBar
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        p.isMovableByWindowBackground = false
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false

        // The hosting view goes inside a plain container rather than being the
        // contentView directly: as contentView, NSHostingView propagates the
        // SwiftUI layout's intrinsic size up and resizes the window itself,
        // which stretched the panel to ~1200pt and pushed the character far
        // below the bottom of the screen.
        let container = NSView(frame: NSRect(origin: .zero, size: panelSize))
        let view = NSHostingView(rootView: blankView())
        container.addSubview(view)
        // NSHostingView defaults translatesAutoresizingMaskIntoConstraints to
        // false, so setting .frame/.autoresizingMask on it does nothing and it
        // sizes itself to SwiftUI's intrinsic content instead. Pin all four
        // edges so the SwiftUI layout gets exactly the panel's box — that's
        // what makes bottom alignment put the character's feet on the bottom
        // edge of the screen.
        view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            view.topAnchor.constraint(equalTo: container.topAnchor),
            view.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        p.contentView = container
        p.setContentSize(panelSize)

        hosting = view
        panel = p
        return p
    }

    private func blankView() -> CharacterOverlayView {
        CharacterOverlayView(message: "", actions: [], frames: sprites.walk,
                             facingLeft: true, loops: true, showBubble: false,
                             size: panelSize)
    }

    private func render(frames: [NSImage], facingLeft: Bool, loops: Bool,
                        bubble: Bool, celebrating: Bool = false) {
        hosting?.rootView = CharacterOverlayView(
            message: message,
            actions: actions,
            frames: frames,
            facingLeft: facingLeft,
            loops: loops,
            showBubble: bubble,
            size: panelSize,
            celebrating: celebrating
        )
    }

    /// The pose he holds while talking. `idle` and not `wave`: the wave frames
    /// are cropped at the thigh, so standing in them looks like he's sunk into
    /// the floor.
    private var standingFrames: [NSImage] {
        if let idle = sprites.idle { return [idle] }
        return sprites.walk
    }

    private func hide() {
        walkTimer?.invalidate()
        timeoutTimer?.invalidate()
        panel?.orderOut(nil)
        phase = .hidden
    }

    // MARK: Geometry

    /// The screen the user is actually looking at — the one holding the cursor.
    private func targetScreen() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
    }

    /// Bottom-right, sitting just above the Dock rather than behind it.
    private func restingOrigin(on screen: NSScreen) -> NSPoint {
        NSPoint(x: screen.visibleFrame.maxX - panelSize.width - edgeInset,
                y: screen.visibleFrame.minY)
    }

    // MARK: Animation

    /// Slides the panel horizontally with an ease-in-out curve while the walk
    /// cycle plays independently — decoupling the two keeps the footfalls even
    /// no matter how far he has to travel.
    private func animate(from startX: CGFloat, to endX: CGFloat, completion: @escaping () -> Void) {
        walkTimer?.invalidate()
        let start = Date()

        walkTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] timer in
            guard let self, let panel = self.panel else {
                timer.invalidate()
                return
            }
            let raw = min(Date().timeIntervalSince(start) / self.walkDuration, 1)
            let eased = raw < 0.5
                ? 2 * raw * raw
                : 1 - pow(-2 * raw + 2, 2) / 2
            let x = startX + (endX - startX) * eased
            panel.setFrameOrigin(NSPoint(x: x, y: panel.frame.origin.y))

            if raw >= 1 {
                timer.invalidate()
                self.walkTimer = nil
                completion()
            }
        }
    }

    private func scheduleTimeout(_ timeout: TimeInterval?) {
        timeoutTimer?.invalidate()
        guard let timeout else { return }
        timeoutTimer = Timer.scheduledTimer(withTimeInterval: timeout, repeats: false) { [weak self] _ in
            self?.onTimeout?()
            self?.dismiss()
        }
    }
}
