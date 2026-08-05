import SwiftUI

/// Plays a frame sequence at a fixed rate.
///
/// `.interpolation(.none)` is the whole point: scaling pixel art with the
/// default smoothing turns crisp edges to mush. The timer only runs while the
/// view is on screen, so the closed menu panel costs nothing.
struct SpriteAnimationView: View {
    let frames: [NSImage]
    var fps: Double = 10
    var loops: Bool = true

    @State private var index = 0

    var body: some View {
        Group {
            if frames.isEmpty {
                Color.clear
            } else {
                Image(nsImage: frames[min(index, frames.count - 1)])
                    .resizable()
                    .interpolation(.none)
                    .aspectRatio(contentMode: .fit)
            }
        }
        .onReceive(Timer.publish(every: 1 / fps, on: .main, in: .common).autoconnect()) { _ in
            guard frames.count > 1 else { return }
            let next = index + 1
            if next >= frames.count {
                index = loops ? 0 : frames.count - 1
            } else {
                index = next
            }
        }
    }
}

/// A single still frame, with the same no-smoothing rule.
struct SpriteImageView: View {
    let image: NSImage?

    var body: some View {
        if let image {
            Image(nsImage: image)
                .resizable()
                .interpolation(.none)
                .aspectRatio(contentMode: .fit)
        } else {
            Color.clear
        }
    }
}
