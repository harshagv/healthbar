# Upright — Project Guide

A multi-app repo of macOS menu-bar agents. Each app lives under `apps/<Name>/`;
build tooling, scripts and CI at the root are generic over the app name.

- **Upright** — reads AirPods head-motion sensors (Apple Core Motion) to detect
  forward-head/slouching posture and nudges the user to sit up straight.
- **MiniMe** — hydration tracking and 60-minute eye breaks, fronted by a
  pixel-art character. Personal use; not distributed.

## Repo layout

```
apps/<Name>/Sources/              Swift sources (+ SwiftPM resources)
apps/<Name>/Resources/            Info.plist (required), AppIcon.icns (optional)
apps/<Name>/<Name>.entitlements   optional, Developer ID builds only
apps/<Name>/Art/                  master art that is processed, not shipped
```

Adding an app = a directory in that shape + a target and product in
`Package.swift`. Nothing else needs to change.

## Commands

- `make run APP=MiniMe` — build the `.app` bundle and launch it (`APP` defaults
  to `Upright`); `make minime` is shorthand
- `./build.sh [release|debug] [AppName]` — build + assemble + ad-hoc sign
- `make install` / `make uninstall` — copy to / remove from `/Applications`
- `make clean` — remove `.build` (shared by all apps)
- `swift scripts/make_icon.swift` — regenerate `apps/Upright/Resources/AppIcon.icns`
- `swift scripts/make_cheer_sprite.swift "$PWD" [scale]` — rebuild the full-body
  `cheer_*` frames by compositing `wave` onto `idle`'s legs. Run it *after*
  `slice_sprites.swift`; it consumes that script's output, not the sheet.
- `swift scripts/slice_sprites.swift "$PWD" [sourceFile]` — regenerate MiniMe's
  sprite frames (defaults to `source_adobe.png`; keys off alpha when the sheet
  has one, otherwise flood-fills from the edges)

Requirements: macOS 14+, Xcode or Command Line Tools (Swift 5.9+). Real Upright
testing needs AirPods Pro/3/Max or Beats Fit Pro.

## Architecture (`apps/Upright/Sources/`)

- `UprightApp.swift` — `@main` App shell; installs `AppDelegate` via
  `NSApplicationDelegateAdaptor` and exposes only an empty `Settings` scene.
  Runs as an `LSUIElement` agent (no Dock icon).
- `AppDelegate.swift` — AppKit lifecycle. Owns the `NSStatusItem` and a lazily
  built `NSPopover` hosting `MenuContentView`. Drives the status glyph from
  `AppState.$menuBarSymbolName` (changes only) and sets `AppState.popoverIsOpen`
  so the UI does no work while the panel is closed.
- `AppState.swift` — `ObservableObject` view-model. Wires motion → analyzer →
  alerts; owns settings (UserDefaults), session stats, and history flushing.
  Per-sample UI publishing (live pitch, chart) is gated on `popoverIsOpen`;
  session counters are plain (non-`@Published`) to avoid idle churn.
- `HeadphoneMotionService.swift` — `CMHeadphoneMotionManager` wrapper. Streams
  pitch (degrees) via an `onMotion` callback (roll/yaw no longer computed);
  only connection/availability/error are `@Published`. Reports connection
  through the delegate.
- `UprightAnalyzer.swift` — baseline calibration, low-pass filter, threshold +
  hold + hysteresis → `UprightState` (`.unknown` / `.good` / `.bad`).
- `AudioDeviceMonitor.swift` — CoreAudio default-output-device watcher; reports
  whether AirPods/headphones are connected even when not monitoring.
- `AlertManager.swift` — sound (`NSSound`) + spoken cue (`AVSpeechSynthesizer`) +
  notification (`UNUserNotificationCenter`), with a cooldown.
- `HistoryStore.swift` — per-day aggregates (`DayStat`) persisted to UserDefaults
  JSON; `lastDays(n)` powers the 7-day chart.
- `MenuContentView.swift` — SwiftUI menu UI: status, live meter, session stats +
  chart, collapsible History and Settings.

Other: `apps/Upright/Resources/Info.plist` (bundle id `com.upright.app`,
`LSUIElement`, `NSMotionUsageDescription`, version),
`apps/Upright/Resources/AppIcon.icns` (generated),
`apps/Upright/Upright.entitlements` (headphone-motion — Developer ID builds
ONLY, never ad-hoc), `build.sh` / `Makefile` (bundle assembly + signing).

## Architecture (`apps/MiniMe/Sources/`)

- `MiniMeApp.swift` / `AppDelegate.swift` — same agent shell as Upright: status
  item, lazily built `NSPopover`, `popoverIsOpen` gating.
- `AppState.swift` — settings (UserDefaults via `didSet`), today's hydration,
  and a 60-second tick that catches local-midnight rollover. The menu-bar glyph
  is driven by `menuBarStep` (progress quantised to 25% steps) so logging a
  glass redraws the status item at most four times a day.
- `HydrationTracker.swift` — pure pacing maths. Pro-rata against the active
  window, so MiniMe talks in deficits ("800 ml behind") not remainders.
- `HistoryStore.swift` — per-day `DayStat` (water, breaks taken/skipped, the
  goal in force that day) in UserDefaults JSON, pruned to 90 days; streaks.
- `SpriteLibrary.swift` — loads pixel-art frames from `Bundle.module`; warns on
  stderr if the resource bundle is missing rather than rendering nothing.
- `SpriteAnimationView.swift` — frame player; `.interpolation(.none)` keeps the
  pixels crisp when scaled.
- `StatusGlyph.swift` — hand-drawn template ring for the menu bar.

Bundle id `com.minime.app`. `NSCameraUsageDescription` is present because break
deferral asks whether the camera is busy — MiniMe never captures video.

## How detection works

1. Stream head pitch (degrees) from the AirPods.
2. User clicks **Calibrate** while upright → baseline pitch captured.
3. Live pitch is low-pass filtered (alpha 0.2); `drop = baseline - smoothed`
   (the `invert` setting flips the sign).
4. `drop >= threshold` sustained for `holdSeconds` → `.bad`; under threshold for
   `recoverSeconds` → `.good` (hysteresis).
5. `.bad` triggers `AlertManager` (respecting cooldown). Sessions are logged to
   `HistoryStore` on stop / recalibrate / quit (≥ 5s sessions only).

## Conventions

- **No third-party dependencies** — Apple frameworks only. Do not add SwiftPM deps.
- **Main thread everywhere** — motion updates arrive on `.main`; keep all
  `@Published` mutations on main. The project intentionally avoids `@MainActor`
  isolation churn (tools 5.9 / Swift 5 language mode).
- Persisted settings are `@Published` vars in `AppState` whose `didSet` writes to
  UserDefaults.
- Match existing style: small focused types, clear names, comments explain *why*.

## Critical gotchas (do NOT reintroduce)

- **AMFI kill:** ad-hoc signing with the restricted
  `com.apple.developer.headphone-motion` entitlement makes macOS SIGKILL the app
  on launch (exit 137). `build.sh` ad-hoc signs WITHOUT entitlements; only apply
  them when a real `SIGN_IDENTITY` (Developer ID) is set.
- **Must run as a signed `.app` bundle** — Core Motion and
  `UNUserNotificationCenter` need a bundle id; a bare binary won't get permissions.
- **Launch from a non-hidden path** — LaunchServices refuses to `open` apps from
  `.build/`; that's why `make install` copies to `/Applications`.
- **Homebrew source build** uses `swift build --disable-sandbox` (SwiftPM's
  nested sandbox fails inside Homebrew's sandbox). Keep that flag in `build.sh`.
- **No AirPods haptics API** — nudges are sound/voice/notification only.
- **Resource bundles are per-app.** SwiftPM drops `<Package>_<Target>.bundle`
  into a bin directory *shared by every product*, so `build.sh` copies only
  `*_<AppName>.bundle`. A bare `*.bundle` glob staples one app's resources into
  another's bundle (Upright shipped MiniMe's sprites this way once).
- **`Bundle.module` needs the bundle inside `Contents/Resources`** — it compiles
  fine without it and traps at runtime in the assembled app. `SpriteLibrary`
  warns on stderr instead of silently rendering nothing.
- **Personal Voice works ad-hoc.** `AVSpeechSynthesizer.requestPersonalVoiceAuthorization()`
  returns `.authorized` from an ad-hoc signed bundle — no Developer ID and no
  entitlement, so it avoids the AMFI trap above. Verified on macOS 26.5.1.

## Distribution

- Main repo: `harshagv/healthbar` (MIT). **Currently private** — the Homebrew
  cask and any release download only work for others once it is public.
- `.github/workflows/release.yml` discovers apps from `apps/`, builds each on a
  macOS runner via a matrix, and attaches two assets per app to the GitHub
  Release on tag pushes:
  - `<App>.zip` — stable filename; this is what the cask downloads
  - `<App>.dmg` — drag-to-Applications installer built with `hdiutil`
- Tag routing:
  - `v1.2.3` → **every app**, published together on one release
  - `minime-v0.1.0` / `<app>-v*` → that app alone
  - branch push, PR or manual run → every app, build only, nothing published
- Matrix jobs append to the same release, which is what lets one `v*` tag put
  every app's bundles on a single release page.
- Both apps have a Homebrew cask (`Casks/upright.rb`, `Casks/minime.rb`). The
  cask token is the app name lowercased and is independent of the repo name.
- `scripts/update-cask.sh [App] [version]` fills in `version` + `sha256` from a
  published release, so checksums are never hand-copied. It derives the tag the
  same way CI does: `v<version>` for Upright, `<app>-v<version>` for everything
  else.
- Homebrew tap: shared repo `harshagv/homebrew-tap` → `Casks/upright.rb`
  (a reference copy lives at `Casks/upright.rb` here). End users need no Xcode.
- Install: `brew install --cask harshagv/tap/upright`

### Cutting a release

Normally: put `[release]` in the commit message and push to `main`. CI computes
the next version, builds, tags and publishes. Nothing to bump by hand.

```bash
git commit -m "feat: eye-break overlay [release]"   # patch bump
git commit -m "feat: eye-break overlay [release:minor]"
git commit -m "feat!: new storage format [release:major]"
```

Also available: **Actions → Build & Release → Run workflow** with
`publish=true`, a bump level, and an app name (or `all`) — the same thing
without a commit. Hand-pushed `vX.Y.Z` / `<app>-vX.Y.Z` tags still work and
release at exactly that version.

**Versions come from git tags, not Info.plist.** The latest tag matching the
app's scheme is incremented, stamped into Info.plist at build time so the
bundle agrees with its tag, then committed back to `main` by the
`record-versions` job (`[skip ci]`, so it doesn't loop). An app with no tag yet
releases at whatever its plist already says, rather than inventing a version
ahead of it. `CFBundleVersion` is set to the workflow run number.

Careless trigger: `[release]` matches **anywhere** in the message, so a commit
that merely mentions it in prose will publish.

Afterwards, sync the cask: `TAP_DIR=~/Documents/homebrew-tap scripts/update-cask.sh [App]`
reads the version from Info.plist (now current) and fills in the `sha256`.

Note: builds are ad-hoc signed (no Developer ID); Gatekeeper reports downloads
as "damaged" until quarantine is cleared. The release body, the bundled
`INSTALL.txt` and the cask caveats all give the `xattr -dr com.apple.quarantine`
fix.

**Artifacts are not a distribution channel.** GitHub Actions artifacts return
401 to anyone not logged in — even on a public repo — and expire after 90 days.
Only release assets are publicly downloadable.

## Testing

No XCTest suite yet. Verify by: a clean build, a launch smoke test (`open` the
app → `pgrep -x Upright` → quit), and — with hardware — Start → Calibrate →
slouch → confirm the nudge fires and stats/history update.
