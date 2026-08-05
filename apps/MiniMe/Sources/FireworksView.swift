import SwiftUI

/// Fireworks for the celebration.
///
/// Square sparks rather than round ones, drawn without anti-aliasing, so they
/// read as part of the same pixel-art world as the character instead of looking
/// like a different medium pasted on top.
///
/// Everything is drawn in a single `Canvas` driven by one timeline, so the whole
/// effect is one view and one redraw per frame no matter how many sparks.
struct FireworksView: View {

    var burstCount = 4
    var duration: Double = 2.6

    private struct Burst {
        let center: CGPoint      // unit space, 0…1
        let delay: Double
        let color: Color
        let sparks: Int
        let spin: Double
    }

    private let bursts: [Burst]
    @State private var start = Date()

    init(burstCount: Int = 4, duration: Double = 2.6) {
        self.burstCount = burstCount
        self.duration = duration

        let palette: [Color] = [
            Color(red: 1.00, green: 0.78, blue: 0.25),   // gold
            Color(red: 1.00, green: 0.42, blue: 0.35),   // coral
            Color(red: 0.45, green: 0.80, blue: 1.00),   // sky
            Color(red: 0.72, green: 0.95, blue: 0.45),   // lime
            Color(red: 0.95, green: 0.55, blue: 0.95)    // orchid
        ]

        bursts = (0..<burstCount).map { i in
            Burst(
                center: CGPoint(x: Double.random(in: 0.15...0.85),
                                y: Double.random(in: 0.10...0.55)),
                delay: Double(i) * 0.28 + Double.random(in: 0...0.12),
                color: palette[i % palette.count],
                sparks: Int.random(in: 10...14),
                spin: Double.random(in: 0...(.pi * 2))
            )
        }
    }

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let now = timeline.date.timeIntervalSince(start)
                // Pixel art: never smooth the sparks.
                context.addFilter(.alphaThreshold(min: 0.02))

                for burst in bursts {
                    let local = now - burst.delay
                    guard local >= 0, local <= duration else { continue }
                    let p = local / duration

                    // Fast out, slow to a stop — the shape of a real burst.
                    let spread = 1 - pow(1 - p, 3)
                    let fade = 1 - p
                    guard fade > 0 else { continue }

                    let origin = CGPoint(x: burst.center.x * size.width,
                                         y: burst.center.y * size.height)
                    let radius = min(size.width, size.height) * 0.34 * spread
                    // Gravity, so the tail of the burst droops.
                    let drop = pow(p, 2) * 34

                    for s in 0..<burst.sparks {
                        let angle = burst.spin + (Double(s) / Double(burst.sparks)) * .pi * 2
                        let jitter = 0.82 + Double((s * 37) % 100) / 320
                        let x = origin.x + cos(angle) * radius * jitter
                        let y = origin.y + sin(angle) * radius * jitter + drop

                        let side: CGFloat = p < 0.35 ? 5 : 3
                        let rect = CGRect(x: x - side / 2, y: y - side / 2, width: side, height: side)
                        context.fill(Path(rect), with: .color(burst.color.opacity(fade)))
                    }

                    // A brief flash at the origin as it goes off.
                    if p < 0.14 {
                        let flash = (0.14 - p) / 0.14
                        let side: CGFloat = 8 * flash + 3
                        let rect = CGRect(x: origin.x - side / 2, y: origin.y - side / 2,
                                          width: side, height: side)
                        context.fill(Path(rect), with: .color(.white.opacity(flash)))
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .onAppear { start = Date() }
    }
}
