cask "minime" do
  version "0.1.0"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"   # auto-set by scripts/update-cask.sh MiniMe

  # MiniMe releases are tagged <app>-v<version>, not v<version> — a bare v* tag
  # is routed to Upright alone for backwards compatibility with the old
  # single-app repo. See .github/workflows/release.yml.
  url "https://github.com/harshagv/healthbar/releases/download/minime-v#{version}/MiniMe.zip",
      verified: "github.com/harshagv/healthbar/"
  name "MiniMe"
  desc "Menu-bar hydration tracker and eye-break reminder fronted by a pixel-art character"
  homepage "https://github.com/harshagv/healthbar"

  depends_on macos: :sonoma   # macOS 14+ (symbol form means "this version or newer")

  app "MiniMe.app"

  caveats <<~EOS
    MiniMe is a menu-bar agent (no Dock icon) and is ad-hoc signed (no Apple
    Developer ID). If macOS reports it "cannot be opened because the developer
    cannot be verified" or that it is "damaged", clear the quarantine flag once:

      xattr -dr com.apple.quarantine "#{appdir}/MiniMe.app"

    Then open MiniMe from Launchpad/Spotlight; it appears in the menu bar.

    MiniMe asks for camera access only to check whether the camera is already
    busy, so an eye break never dims your screen mid-call. It never records
    video, and declining simply means breaks are not deferred during calls.

    Spoken nudges are off by default. Turning them on uses a Personal Voice if
    you have one set up in System Settings, otherwise a system voice.
  EOS

  zap trash: [
    "~/Library/Preferences/com.minime.app.plist",
  ]
end
