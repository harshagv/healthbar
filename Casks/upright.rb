cask "upright" do
  version "0.1.1"
  sha256 "REPLACE_WITH_UPRIGHT_ZIP_SHA256"   # sha256 of Upright.zip (printed by the release workflow's Summary)

  url "https://github.com/harshagv/upright/releases/download/v#{version}/Upright.zip",
      verified: "github.com/harshagv/upright/"
  name "Upright"
  desc "Menu-bar app that nudges you to sit up straight using AirPods motion sensors"
  homepage "https://github.com/harshagv/upright"

  depends_on macos: :sonoma   # macOS 14+ (symbol form means "this version or newer")

  app "Upright.app"

  caveats <<~EOS
    Upright is a menu-bar agent (no Dock icon) and is ad-hoc signed (no Apple
    Developer ID). If macOS reports it "cannot be opened because the developer
    cannot be verified" or that it is "damaged", clear the quarantine flag once:

      xattr -dr com.apple.quarantine "#{appdir}/Upright.app"

    Then open Upright from Launchpad/Spotlight; it appears in the menu bar.
    Real posture detection needs AirPods Pro/3/Max or Beats Fit Pro.
  EOS

  zap trash: [
    "~/Library/Preferences/com.upright.app.plist",
  ]
end
