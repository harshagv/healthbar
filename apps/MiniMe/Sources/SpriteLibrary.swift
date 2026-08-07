import AppKit

/// MiniMe's pixel-art frames, sliced from the reference sheet by
/// `scripts/slice_sprites.swift` and packaged as a resource folder.
///
/// Loaded once and held for the process lifetime: the whole set is a couple of
/// hundred kilobytes, and paying for it lazily during a break animation would
/// risk a stutter at exactly the wrong moment.
final class SpriteLibrary {

    static let shared = SpriteLibrary()

    /// 8-frame loop. Frames share a canvas, so the feet stay planted.
    let walk: [NSImage]
    /// 3-frame entrance with motion streaks — the bottom-right arrival.
    let entrance: [NSImage]
    /// 4-frame wave: arm up, hold, down. Cropped at the thigh — usable as a
    /// close-up, never as a standing pose.
    let wave: [NSImage]
    /// Full-body arm-raised frames, composited from `wave` + `idle` by
    /// `scripts/make_cheer_sprite.swift`. These are what the celebration uses,
    /// because `wave` alone would render a legless character.
    let cheer: [NSImage]
    let idle: NSImage?

    let glassesOn: NSImage?
    let glassesOff: NSImage?

    let neutral: NSImage?
    let smile: NSImage?
    let wink: NSImage?
    let serious: NSImage?
    let thinking: NSImage?
    let surprised: NSImage?
    /// Sunglasses and sparkles — reserved for hitting the daily goal.
    let shades: NSImage?

    private init() {
        walk     = SpriteLibrary.sequence(prefix: "walk", count: 8)
        entrance = SpriteLibrary.sequence(prefix: "entrance", count: 3)
        wave     = SpriteLibrary.sequence(prefix: "wave", count: 4)
        cheer    = SpriteLibrary.sequence(prefix: "cheer", count: 2)
        idle     = SpriteLibrary.load("idle")

        glassesOn  = SpriteLibrary.load("glasses_on")
        glassesOff = SpriteLibrary.load("glasses_off")

        neutral   = SpriteLibrary.load("expr_neutral")
        smile     = SpriteLibrary.load("expr_smile")
        wink      = SpriteLibrary.load("expr_wink")
        serious   = SpriteLibrary.load("expr_serious")
        thinking  = SpriteLibrary.load("expr_thinking")
        surprised = SpriteLibrary.load("expr_surprised")
        shades    = SpriteLibrary.load("expr_shades")

        // Silence means the resource bundle landed where Bundle.module expects.
        // If build.sh ever stops copying it into Contents/Resources the UI would
        // just render nothing, so say so out loud instead.
        if !isLoaded {
            FileHandle.standardError.write(Data(
                "MiniMe: sprite frames failed to load — is Sprites/ in the resource bundle?\n".utf8))
        }
    }

    private static func load(_ name: String) -> NSImage? {
        guard let url = Bundle.module.url(forResource: name, withExtension: "png", subdirectory: "Sprites") else {
            return nil
        }
        return NSImage(contentsOf: url)
    }

    private static func sequence(prefix: String, count: Int) -> [NSImage] {
        (0..<count).compactMap { load(String(format: "%@_%02d", prefix, $0)) }
    }

    /// True when the resource folder made it into the bundle. `build.sh` copies
    /// SwiftPM's `.bundle` into Contents/Resources; if that ever regresses this
    /// goes false rather than the app crashing on a force-unwrap.
    var isLoaded: Bool { !walk.isEmpty && idle != nil }
}
