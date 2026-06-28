class Upright < Formula
  desc "Menu-bar app that nudges you to sit up straight using AirPods motion sensors"
  homepage "https://github.com/harshagv/upright"
  url "https://github.com/harshagv/upright/archive/refs/tags/v0.1.2.tar.gz"
  sha256 "REPLACE_WITH_TARBALL_SHA256"
  license "MIT"
  head "https://github.com/harshagv/upright.git", branch: "main"

  depends_on :macos
  depends_on xcode: ["15.0", :build]

  def install
    # build.sh compiles, assembles, and ad-hoc signs the .app bundle.
    # --disable-sandbox is already inside build.sh (required under Homebrew).
    system "./build.sh", "release"

    bin_path = Utils.safe_popen_read(
      "swift", "build", "-c", "release", "--disable-sandbox", "--show-bin-path"
    ).chomp

    prefix.install "#{bin_path}/Upright.app"
    # A CLI shim that launches the menu-bar app without going through
    # LaunchServices `open` (which refuses apps in hidden/Cellar paths).
    bin.write_exec_script "#{prefix}/Upright.app/Contents/MacOS/Upright"
  end

  def caveats
    <<~EOS
      Upright is a menu-bar agent (no Dock icon). Start it with:
        upright

      On first launch, macOS will ask for Motion and Notification permission.
      Real posture detection needs AirPods Pro/3/Max or Beats Fit Pro.
    EOS
  end

  test do
    assert_path_exists prefix/"Upright.app/Contents/MacOS/Upright"
  end
end
