cask "klipboard" do
  version "0.1.0"
  sha256 :no_check

  repo = ENV.fetch("HOMEBREW_KLIPBOARD_REPO", "akai-49/Klipboard")
  url "https://github.com/#{repo}/releases/download/v#{version}/Klipboard-#{version}.dmg"
  name "Klipboard"
  desc "Lightweight native macOS clipboard manager with global hotkeys"
  homepage "https://github.com/#{repo}"

  depends_on macos: ">= :sonoma"

  app "Klipboard.app"

  postflight do
    system_command "/usr/bin/xattr",
                   args: ["-cr", "#{appdir}/Klipboard.app"],
                   sudo: false
  end

  zap trash: [
    "~/Library/Application Support/Klipboard",
    "~/Library/Preferences/com.abhishek.Klipboard.plist",
  ]
end
