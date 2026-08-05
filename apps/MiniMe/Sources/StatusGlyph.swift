import AppKit

/// The menu-bar icon: a ring that fills with the day's hydration progress.
///
/// Drawn by hand rather than composed from SF Symbols because the fill needs to
/// be an exact fraction, and returned as a *template* image so macOS tints it
/// for light and dark menu bars automatically. Template images keep their alpha,
/// which is what lets the unfilled track read as a faint ring.
enum StatusGlyph {

    /// Progress is quantised by the caller (25% steps) so the status item
    /// redraws a handful of times a day rather than on every sip logged.
    static func ring(progress: Double, size: CGFloat = 18) -> NSImage {
        let clamped = min(max(progress, 0), 1)

        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let lineWidth: CGFloat = 2
            let box = rect.insetBy(dx: lineWidth, dy: lineWidth)
            let center = NSPoint(x: box.midX, y: box.midY)
            let radius = box.width / 2

            let track = NSBezierPath(ovalIn: box)
            track.lineWidth = lineWidth
            NSColor.black.withAlphaComponent(0.35).setStroke()
            track.stroke()

            if clamped > 0 {
                // Clockwise from 12 o'clock, so it reads like a filling glass.
                let arc = NSBezierPath()
                arc.appendArc(withCenter: center,
                              radius: radius,
                              startAngle: 90,
                              endAngle: 90 - 360 * clamped,
                              clockwise: true)
                arc.lineWidth = lineWidth
                arc.lineCapStyle = .round
                NSColor.black.setStroke()
                arc.stroke()
            }
            return true
        }

        image.isTemplate = true
        return image
    }
}
