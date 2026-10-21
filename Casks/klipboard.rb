cask "klipboard" do
  version "0.1.0"
  sha256 "54c5205cec87293e127be02f22f624d6fe72f1acd859a1664d8d83f93a7943bd"

  url "https://github.com/abhishek/Klipboard/releases/download/v#{version}/Klipboard-#{version}.dmg"
  name "Klipboard"
  desc "Lightweight native macOS clipboard manager with global hotkeys"
  homepage "https://github.com/abhishek/Klipboard"

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
