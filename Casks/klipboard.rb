cask "klipboard" do
  version :latest
  sha256 :no_check

  repo = ENV.fetch("HOMEBREW_KLIPBOARD_REPO", "akai-49/Klipboard")
  url "https://github.com/#{repo}/releases/latest/download/Klipboard.dmg"
  name "Klipboard"
  desc "Clipboard history, snippets and paste stack for the menu bar"
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
