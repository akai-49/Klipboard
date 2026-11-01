cask "klipboard" do
  version "0.4.0"
  sha256 "SHA256_PLACEHOLDER"

  url "https://github.com/akai-49/Klipboard/releases/download/v#{version}/Klipboard-#{version}.dmg"
  name "Klipboard"
  desc "Clipboard history, snippets and paste stack for the menu bar"
  homepage "https://github.com/akai-49/Klipboard"

  auto_updates true
  depends_on macos: :sonoma

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
