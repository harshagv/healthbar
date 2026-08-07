import AppKit
import CoreGraphics

// Builds full-body "arms up" cheer frames for MiniMe.
//
// The sheet's wave row is drawn about 1.6x larger than the walk/idle rows and
// is cropped at the thigh, so using it as a standing pose renders a legless
// character. This composites the two: the wave frame scaled down to idle's
// body scale for everything above the thigh, and idle's own pixels for the
// legs below it. The join is a hard horizontal cut rather than an alpha blend —
// both sides are flat denim there, so a cut is invisible where a blend would
// smear two slightly different blues together.
//
// Run:  swift scripts/make_cheer_sprite.swift "$PWD" [scale] [dx] [dy]
//   scale  wave→idle size ratio      (default 0.78)
//   dx     horizontal nudge, px      (default 0)
//   dy     vertical nudge, px        (default 0)

guard CommandLine.arguments.count > 1 else {
    fatalError("usage: swift scripts/make_cheer_sprite.swift <repo-root> [scale] [dx] [dy]")
}
let root = CommandLine.arguments[1]
let scale = CommandLine.arguments.count > 2 ? Double(CommandLine.arguments[2])! : 0.78
let dx = CommandLine.arguments.count > 3 ? Int(CommandLine.arguments[3])! : 0
let dy = CommandLine.arguments.count > 4 ? Int(CommandLine.arguments[4])! : 0

let spritesDir = "\(root)/apps/MiniMe/Sources/Sprites"

struct Bitmap {
    var w: Int, h: Int, px: [UInt8]

    static func load(_ path: String) -> Bitmap? {
        guard let img = NSImage(contentsOfFile: path),
              let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let w = cg.width, h = cg.height
        var px = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        return Bitmap(w: w, h: h, px: px)
    }

    @inline(__always) func alpha(_ x: Int, _ y: Int) -> Int {
        guard x >= 0, y >= 0, x < w, y < h else { return 0 }
        return Int(px[(y * w + x) * 4 + 3])
    }

    /// Nearest-neighbour only — pixel art must never be resampled smoothly.
    func scaled(by s: Double) -> Bitmap {
        let nw = max(1, Int((Double(w) * s).rounded()))
        let nh = max(1, Int((Double(h) * s).rounded()))
        var out = [UInt8](repeating: 0, count: nw * nh * 4)
        for y in 0..<nh {
            let sy = min(h - 1, Int(Double(y) / s))
            for x in 0..<nw {
                let sx = min(w - 1, Int(Double(x) / s))
                let si = (sy * w + sx) * 4, di = (y * nw + x) * 4
                out[di] = px[si]; out[di + 1] = px[si + 1]
                out[di + 2] = px[si + 2]; out[di + 3] = px[si + 3]
            }
        }
        return Bitmap(w: nw, h: nh, px: out)
    }

    /// Horizontal centre of opaque pixels in a row band — used to line the two
    /// sprites up on the body rather than on their differing bounding boxes.
    func centroidX(rows: Range<Int>) -> Int {
        var sum = 0, count = 0
        for y in rows where y >= 0 && y < h {
            for x in 0..<w where alpha(x, y) > 40 { sum += x; count += 1 }
        }
        return count > 0 ? sum / count : w / 2
    }

    func firstOpaqueRow() -> Int {
        for y in 0..<h {
            for x in 0..<w where alpha(x, y) > 40 { return y }
        }
        return 0
    }

    func write(to path: String) {
        var copy = px
        guard let ctx = CGContext(data: &copy, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let image = ctx.makeImage() else { return }
        let rep = NSBitmapImageRep(cgImage: image)
        rep.size = NSSize(width: w, height: h)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }
}

guard let idle = Bitmap.load("\(spritesDir)/idle.png") else {
    fatalError("missing idle.png — run slice_sprites.swift first")
}

print("idle: \(idle.w)x\(idle.h)   scale=\(scale) dx=\(dx) dy=\(dy)")

// The two wave frames with the arm actually raised.
for (index, waveName) in ["wave_01", "wave_02"].enumerated() {
    guard let wave = Bitmap.load("\(spritesDir)/\(waveName).png") else {
        print("  skip \(waveName) (missing)"); continue
    }
    let small = wave.scaled(by: scale)

    // Align on the torso, not the bounding box: the raised arm makes the wave
    // frame's box wider and taller on one side, so box-alignment would shove
    // the body sideways.
    let waveTorso = small.centroidX(rows: (small.h * 55 / 100)..<(small.h * 90 / 100))
    let idleTorso = idle.centroidX(rows: (idle.h * 30 / 100)..<(idle.h * 55 / 100))

    // Head tops line up once the arm is excluded by starting below it.
    let offsetX = idleTorso - waveTorso + dx
    let offsetY = idle.firstOpaqueRow() - small.firstOpaqueRow() + dy

    // Seam: the bottom of the scaled wave, which is mid-thigh.
    let seam = offsetY + small.h

    var out = Bitmap(w: idle.w, h: idle.h,
                     px: [UInt8](repeating: 0, count: idle.w * idle.h * 4))

    // Legs from idle, below the seam.
    for y in max(0, seam)..<idle.h {
        for x in 0..<idle.w {
            let si = (y * idle.w + x) * 4, di = si
            out.px[di] = idle.px[si]; out.px[di + 1] = idle.px[si + 1]
            out.px[di + 2] = idle.px[si + 2]; out.px[di + 3] = idle.px[si + 3]
        }
    }

    // Everything above the seam from the scaled wave.
    for y in 0..<small.h {
        let dyRow = y + offsetY
        guard dyRow >= 0, dyRow < idle.h, dyRow < seam else { continue }
        for x in 0..<small.w {
            let dxCol = x + offsetX
            guard dxCol >= 0, dxCol < idle.w else { continue }
            let si = (y * small.w + x) * 4
            guard small.px[si + 3] > 0 else { continue }
            let di = (dyRow * idle.w + dxCol) * 4
            out.px[di] = small.px[si]; out.px[di + 1] = small.px[si + 1]
            out.px[di + 2] = small.px[si + 2]; out.px[di + 3] = small.px[si + 3]
        }
    }

    let name = String(format: "cheer_%02d", index)
    out.write(to: "\(spritesDir)/\(name).png")
    print("  \(name).png  \(out.w)x\(out.h)  seam at y=\(seam)  offset=(\(offsetX), \(offsetY))")
}
print("Done.")
