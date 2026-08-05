import AppKit
import SwiftUI
import CoreGraphics

/// A window that can take key focus despite being borderless — needed so Esc
/// reaches us during a break.
private final class KeyableWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Dims every display for the eye break.
///
/// One window per screen at `CGShieldingWindowLevel()`, which covers the menu
/// bar and Dock — a dim that leaves bright strips top and bottom rather defeats
/// the point. The dim ramps in over ~1.2s instead of cutting: a hard flash to
/// black is jarring and a photosensitivity concern.
///
/// Only the screen holding the cursor gets the countdown and the Skip button;
/// the rest just go dark.
final class DimOverlayController {

    private var windows: [NSWindow] = []
    private var hosting: NSHostingView<DimContentView>?
    private var ticker: Timer?
    private var keyMonitor: Any?

    private var remaining = 0
    private var total = 0
    private var message = ""
    private var completion: ((Bool) -> Void)?

    var isActive: Bool { !windows.isEmpty }

    /// `completion(true)` when the break ran its course, `false` when skipped.
    func begin(seconds: Int, message: String, completion: @escaping (Bool) -> Void) {
        guard !isActive else { return }

        self.total = seconds
        self.remaining = seconds
        self.message = message
        self.completion = completion

        let cursorScreen = screenWithCursor()

        for screen in NSScreen.screens {
            let window = KeyableWindow(contentRect: screen.frame,
                                       styleMask: [.borderless],
                                       backing: .buffered,
                                       defer: false)
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            window.ignoresMouseEvents = false
            window.alphaValue = 0
            window.setFrame(screen.frame, display: false)

            if screen == cursorScreen {
                let view = NSHostingView(rootView: content())
                view.translatesAutoresizingMaskIntoConstraints = false
                let container = NSView(frame: screen.frame)
                container.addSubview(view)
                NSLayoutConstraint.activate([
                    view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                    view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                    view.topAnchor.constraint(equalTo: container.topAnchor),
                    view.bottomAnchor.constraint(equalTo: container.bottomAnchor)
                ])
                window.contentView = container
                hosting = view
            } else {
                let plain = NSHostingView(rootView: DimContentView(
                    message: "", remaining: 0, total: seconds, showsChrome: false, onSkip: {}))
                window.contentView = plain
            }

            window.orderFrontRegardless()
            windows.append(window)
        }

        // Take focus so Esc reaches the local monitor. An accessory app has to
        // ask for this explicitly.
        NSApp.activate(ignoringOtherApps: true)
        windows.first?.makeKeyAndOrderFront(nil)

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {          // Esc
                self?.finish(taken: false)
                return nil
            }
            return event
        }

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 1.2
            for window in windows { window.animator().alphaValue = 1 }
        }

        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.remaining -= 1
            if self.remaining <= 0 {
                self.finish(taken: true)
            } else {
                self.hosting?.rootView = self.content()
            }
        }
    }

    func cancel() {
        guard isActive else { return }
        finish(taken: false)
    }

    // MARK: Internals

    private func content() -> DimContentView {
        DimContentView(message: message,
                       remaining: remaining,
                       total: total,
                       showsChrome: true,
                       onSkip: { [weak self] in self?.finish(taken: false) })
    }

    private func finish(taken: Bool) {
        guard isActive else { return }

        ticker?.invalidate()
        ticker = nil
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil

        let closing = windows
        windows = []
        hosting = nil

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.45
            for window in closing { window.animator().alphaValue = 0 }
        } completionHandler: {
            for window in closing { window.orderOut(nil) }
        }

        let done = completion
        completion = nil
        done?(taken)
    }

    private func screenWithCursor() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
    }
}

/// The dim itself plus, on the cursor's screen, the countdown and an escape hatch.
struct DimContentView: View {
    let message: String
    let remaining: Int
    let total: Int
    let showsChrome: Bool
    let onSkip: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.88)

            if showsChrome {
                VStack(spacing: 26) {
                    ZStack {
                        Circle()
                            .stroke(Color.white.opacity(0.18), lineWidth: 6)
                        Circle()
                            .trim(from: 0, to: total > 0 ? CGFloat(remaining) / CGFloat(total) : 0)
                            .stroke(Color.white.opacity(0.9),
                                    style: StrokeStyle(lineWidth: 6, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .animation(.linear(duration: 1), value: remaining)
                        Text("\(remaining)")
                            .font(.system(size: 40, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                    }
                    .frame(width: 132, height: 132)

                    Text(message)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 620)

                    Text("Look at something far away.")
                        .font(.system(size: 15))
                        .foregroundStyle(.white.opacity(0.65))

                    Button("Skip  (esc)") { onSkip() }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 9)
                        .background(Capsule().fill(Color.white.opacity(0.14)))
                        .foregroundStyle(.white.opacity(0.85))
                        .padding(.top, 6)
                }
            }
        }
        .ignoresSafeArea()
    }
}
