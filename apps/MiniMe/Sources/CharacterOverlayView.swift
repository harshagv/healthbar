import SwiftUI

/// A button inside MiniMe's speech bubble.
struct CharacterAction: Identifiable {
    let id = UUID()
    let title: String
    let isPrimary: Bool
    let handler: () -> Void

    init(_ title: String, isPrimary: Bool = false, handler: @escaping () -> Void) {
        self.title = title
        self.isPrimary = isPrimary
        self.handler = handler
    }
}

/// MiniMe standing at the bottom-right of the screen, optionally with something
/// to say. The character never takes clicks — only the bubble does — so an
/// idle MiniMe can't come between you and whatever is underneath.
struct CharacterOverlayView: View {
    let message: String
    let actions: [CharacterAction]
    let frames: [NSImage]
    let facingLeft: Bool
    let loops: Bool
    let showBubble: Bool
    /// The panel's exact size. This must be a definite value, not
    /// `maxWidth/maxHeight: .infinity` — `NSHostingView` reports the SwiftUI
    /// layout's fitting size up to the window, so an unbounded root grew the
    /// panel to 1227pt and dragged its origin to y = -797, putting the
    /// bottom-pinned character far below the screen.
    let size: CGSize
    var celebrating: Bool = false
    var characterHeight: CGFloat = 190

    @State private var hop: CGFloat = 0

    var body: some View {
        // A ZStack rather than a VStack: stacking them vertically made the
        // bubble's height displace the character, sinking his feet below the
        // bottom of the panel (and so below the bottom of the screen). Here he
        // is pinned to the bottom and the bubble floats above his head, so
        // showing or hiding it never moves him.
        ZStack(alignment: .bottom) {
            // The cheer is two frames — at walking speed it reads as a flicker
            // rather than an arm going up and down, so slow it right down.
            SpriteAnimationView(frames: frames, fps: celebrating ? 5 : 12, loops: loops)
                .frame(height: characterHeight)
                // Sprites are drawn walking to the right; flip to walk left.
                .scaleEffect(x: facingLeft ? -1 : 1, y: 1)
                .allowsHitTesting(false)
                .offset(y: hop)
                .onChange(of: celebrating) { startHopIfNeeded() }
                .onAppear { startHopIfNeeded() }

            if showBubble {
                bubble
                    .frame(maxWidth: 500)
                    .padding(.bottom, characterHeight - 8)
            }

            // Above everything, over the bubble and his head.
            if celebrating {
                FireworksView()
            }
        }
        .frame(width: size.width, height: size.height, alignment: .bottom)
    }

    /// Two quick hops. The `wave` frames would read better as a celebration but
    /// they're a half-body crop with no legs, so bouncing the full-body sprite
    /// is the only way to cheer without him appearing cut off at the thigh.
    private func startHopIfNeeded() {
        guard celebrating else {
            hop = 0
            return
        }
        withAnimation(.easeOut(duration: 0.22).repeatCount(4, autoreverses: true)) {
            hop = -22
        }
    }

    private var bubble: some View {
        VStack(spacing: 12) {
            Text(message)
                .font(.system(size: 15, weight: .semibold))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                ForEach(actions) { action in
                    Button(action.title) { action.handler() }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .tint(action.isPrimary ? .accentColor : nil)
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.8), lineWidth: 2)
        )
        .shadow(color: .black.opacity(0.25), radius: 14, y: 5)
    }
}
