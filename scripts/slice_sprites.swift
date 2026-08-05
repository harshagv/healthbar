import AppKit
import CoreGraphics

// Slices apps/MiniMe/Art/source.png (a hand-made reference sheet with labels,
// dividers and a palette strip) into individual transparent PNGs in
// apps/MiniMe/Sources/Sprites/, where SwiftPM can package them.
//
// Run:  swift scripts/slice_sprites.swift "$PWD"
//
// Two things make this more than a grid slice:
//   • The sheet has no alpha. Background is found by flood-filling inward from
//     the edges, so the character's own near-black hair and navy jacket stay
//     opaque — a luminance threshold would punch holes straight through them.
//   • Cells are not uniform, and each section carries caption text above (and,
//     for expressions, below) the art. Within a cell we keep only the tallest
//     run of content rows, which is the character and never the caption.
//
// Frames in an animation share one y-range and one canvas width so the feet
// stay planted; trimming each frame tightly would make the walk cycle jitter.

// Repo root as argv[1]. `swift -interpret` neither reports an absolute
// #filePath nor runs with the repo as its working directory, so neither can be
// relied on to find the sheet.
//   swift scripts/slice_sprites.swift "$PWD"
guard CommandLine.arguments.count > 1 else {
    fatalError("usage: swift scripts/slice_sprites.swift <repo-root>")
}
let root = CommandLine.arguments[1]
let sourcePath = "\(root)/apps/MiniMe/Art/source.png"
let outDir = "\(root)/apps/MiniMe/Sources/Sprites"

guard let img = NSImage(contentsOfFile: sourcePath),
      let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    fatalError("cannot load \(sourcePath)")
}

let w = cg.width, h = cg.height
var buf = [UInt8](repeating: 0, count: w * h * 4)
guard let ctx = CGContext(data: &buf, width: w, height: h, bitsPerComponent: 8,
                          bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    fatalError("no context")
}
ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))

@inline(__always) func rgb(_ x: Int, _ y: Int) -> (Int, Int, Int) {
    let i = (y * w + x) * 4
    return (Int(buf[i]), Int(buf[i + 1]), Int(buf[i + 2]))
}

// MARK: Background mask

let bg = rgb(0, 0)
let tolerance = 40

var isBG = [Bool](repeating: false, count: w * h)
var stack: [Int] = []

func flood(_ x: Int, _ y: Int) {
    guard x >= 0, y >= 0, x < w, y < h else { return }
    let i = y * w + x
    if isBG[i] { return }
    let p = rgb(x, y)
    guard abs(p.0 - bg.0) + abs(p.1 - bg.1) + abs(p.2 - bg.2) <= tolerance else { return }
    isBG[i] = true
    stack.append(i)
}

for x in 0..<w { flood(x, 0); flood(x, h - 1) }
for y in 0..<h { flood(0, y); flood(w - 1, y) }
while let i = stack.popLast() {
    let x = i % w, y = i / w
    flood(x - 1, y); flood(x + 1, y); flood(x, y - 1); flood(x, y + 1)
}

@inline(__always) func isContent(_ x: Int, _ y: Int) -> Bool { !isBG[y * w + x] }

// MARK: Segmentation helpers

func runs(_ counts: [Int], threshold: Int, minLength: Int) -> [(lo: Int, hi: Int)] {
    var result: [(Int, Int)] = []
    var start: Int? = nil
    for (i, c) in counts.enumerated() {
        if c > threshold, start == nil { start = i }
        if c <= threshold, let s = start {
            if i - s >= minLength { result.append((s, i - 1)) }
            start = nil
        }
    }
    if let s = start, counts.count - s >= minLength { result.append((s, counts.count - 1)) }
    return result
}

/// Tallest run of content rows inside a column range — the character, not the caption.
func artRows(xLo: Int, xHi: Int, yLo: Int, yHi: Int) -> (lo: Int, hi: Int)? {
    var counts = [Int](repeating: 0, count: h)
    for y in yLo...yHi {
        var c = 0
        for x in xLo...xHi where isContent(x, y) { c += 1 }
        counts[y] = c
    }
    return runs(counts, threshold: 0, minLength: 1).max { ($0.hi - $0.lo) < ($1.hi - $1.lo) }
}

// MARK: Sections
//
// y-bands and the cell semantics within them, measured from the sheet.

struct Section {
    let yLo: Int, yHi: Int
    /// Names in left-to-right order; one per detected cell.
    let names: [String]
    /// Cells sharing a canvas so an animation's frames stay aligned.
    let groups: [String: [String]]
}

let sections: [Section] = [
    Section(yLo: 20, yHi: 340,
            names: (0..<8).map { String(format: "walk_%02d", $0) } + ["idle"],
            groups: ["walk": (0..<8).map { String(format: "walk_%02d", $0) }]),
    Section(yLo: 355, yHi: 645,
            names: (0..<4).map { String(format: "wave_%02d", $0) } + ["glasses_on", "glasses_off"],
            groups: ["wave": (0..<4).map { String(format: "wave_%02d", $0) }]),
    Section(yLo: 660, yHi: 968,
            names: ["expr_neutral", "expr_smile", "expr_wink", "expr_serious",
                    "expr_thinking", "expr_surprised", "expr_shades"]
                 + (0..<3).map { String(format: "entrance_%02d", $0) },
            groups: ["entrance": (0..<3).map { String(format: "entrance_%02d", $0) }])
]

// MARK: Slice

struct Cell {
    let name: String
    var xLo: Int, xHi: Int, yLo: Int, yHi: Int
}

var cells: [String: Cell] = [:]
var order: [String] = []

for section in sections {
    var colCounts = [Int](repeating: 0, count: w)
    for x in 0..<w {
        var c = 0
        for y in section.yLo...section.yHi where isContent(x, y) { c += 1 }
        colCounts[x] = c
    }
    let cols = runs(colCounts, threshold: 1, minLength: 16)

    guard cols.count == section.names.count else {
        fatalError("section y=\(section.yLo) expected \(section.names.count) cells, found \(cols.count)")
    }

    for (name, col) in zip(section.names, cols) {
        guard let rows = artRows(xLo: col.lo, xHi: col.hi, yLo: section.yLo, yHi: section.yHi) else { continue }
        cells[name] = Cell(name: name, xLo: col.lo, xHi: col.hi, yLo: rows.lo, yHi: rows.hi)
        order.append(name)
    }

    // Align grouped frames onto a shared canvas: common y-range keeps the feet
    // planted, common width keeps the body from sliding side to side.
    for (_, members) in section.groups {
        let present = members.compactMap { cells[$0] }
        guard !present.isEmpty else { continue }
        let yLo = present.map(\.yLo).min()!
        let yHi = present.map(\.yHi).max()!
        for name in members where cells[name] != nil {
            cells[name]!.yLo = yLo
            cells[name]!.yHi = yHi
        }
    }
}

// MARK: Emit

try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

func writePNG(_ cell: Cell, canvasWidth: Int) {
    let cw = canvasWidth
    let ch = cell.yHi - cell.yLo + 1
    let srcW = cell.xHi - cell.xLo + 1
    let xPad = (cw - srcW) / 2

    var out = [UInt8](repeating: 0, count: cw * ch * 4)
    for y in 0..<ch {
        for x in 0..<srcW {
            let sx = cell.xLo + x, sy = cell.yLo + y
            guard isContent(sx, sy) else { continue }
            let si = (sy * w + sx) * 4
            let di = (y * cw + (x + xPad)) * 4
            out[di] = buf[si]; out[di + 1] = buf[si + 1]
            out[di + 2] = buf[si + 2]; out[di + 3] = 255
        }
    }

    guard let octx = CGContext(data: &out, width: cw, height: ch, bitsPerComponent: 8,
                               bytesPerRow: cw * 4, space: CGColorSpaceCreateDeviceRGB(),
                               bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
          let image = octx.makeImage() else { return }

    let rep = NSBitmapImageRep(cgImage: image)
    rep.size = NSSize(width: cw, height: ch)
    guard let data = rep.representation(using: .png, properties: [:]) else { return }
    try? data.write(to: URL(fileURLWithPath: "\(outDir)/\(cell.name).png"))
    print(String(format: "  %-18s %4dx%-4d", (cell.name as NSString).utf8String!, cw, ch))
}

// Grouped frames share the widest cell in their group; everything else is solo.
var groupOf: [String: String] = [:]
for section in sections {
    for (group, members) in section.groups {
        for m in members { groupOf[m] = group }
    }
}
var groupWidth: [String: Int] = [:]
for (name, cell) in cells {
    guard let g = groupOf[name] else { continue }
    groupWidth[g] = max(groupWidth[g] ?? 0, cell.xHi - cell.xLo + 1)
}

print("Writing \(order.count) frames to \(outDir):")
for name in order {
    guard let cell = cells[name] else { continue }
    let width = groupOf[name].flatMap { groupWidth[$0] } ?? (cell.xHi - cell.xLo + 1)
    writePNG(cell, canvasWidth: width)
}
print("Done.")
