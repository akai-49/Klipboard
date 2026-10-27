# Klipboard for macOS

**Klipboard** is a fast, lightweight native macOS clipboard manager built with Swift and AppKit/SwiftUI. It lives quietly in your menu bar, captures text, rich text (RTF), links, images, files, and colors with near-zero idle CPU/memory overhead, and opens instantly from anywhere via a Spotlight-style floating panel.

<p align="center"><img src="docs/screenshot-panel.png" alt="Klipboard panel showing clipboard history" width="650"></p>

## Features

- **Instant Global Shortcut**: Press **`⌥V` (Option + V)** or **`⌘⇧V` (Command + Shift + V)** from any app to toggle the floating clipboard history panel.
- **Direct Paste-Back**: Select any item with `↑` / `↓` and press **`Return`** (or click it) to automatically paste it right into your active app.
- **Multi-Format Capture**:
  - Plain text & code snippets
  - Rich text (RTF)
  - URLs & web links
  - Images (automatically downsampled via `ImageIO` to prevent Retina memory spikes)
  - Files & folders (with quick **Reveal in Finder**)
  - Colors (with live hex preview swatch)
- **Always Running in the Background**: Starts automatically at login (toggle via **Launch at Login** in the menu-bar menu), stays out of the Dock, and keeps running until you choose **Quit Klipboard**.
- **History Survives Restarts**: Everything you copy is saved locally to `~/Library/Application Support/Klipboard/` and restored after a reboot. Images are stored as separate files, so memory stays flat as history grows. Keeps the latest 100 items; pinned and favorite items are never trimmed.
- **Password-Manager Aware**: Content marked concealed/transient by 1Password, Keychain, Bitwarden, etc. ([nspasteboard.org](http://nspasteboard.org) markers) is never recorded.
- **Pin, Favorite & Search**: Real-time instant search across text and source app names, plus pinning (`Pin`) and starring (`Favorite`) so important clips are never auto-trimmed.
- **Ultra-Low Resource Usage**: ~27 MB RAM and ~0% idle CPU. Timer-coalesced pasteboard polling, `NSCache`-backed 64px thumbnail downsampling, off-main-thread disk writes, and zero background animations when idle.
- **Safe by Design**: 100% offline, no network access. Never touches other apps or files outside its own folder.

## Installation

### Option 1: 1-Line Terminal Installer (Recommended — No Gatekeeper Popup)

Downloads the DMG, installs `Klipboard.app` to `/Applications`, clears the macOS quarantine attribute automatically, and launches Klipboard:

```bash
curl -fsSL https://klipboard-beryl.vercel.app/install.sh | bash
```

### Option 2: Drag-and-Drop DMG Installer

1. Download **`Klipboard-0.1.0.dmg`** from [**klipboard-beryl.vercel.app**](https://klipboard-beryl.vercel.app/Klipboard-0.1.0.dmg) or [**GitHub Releases**](https://github.com/akai-49/Klipboard/releases/latest).
2. Double-click **`Klipboard-0.1.0.dmg`** to mount the installer volume.
3. Drag **`Klipboard.app`** onto the **`Applications`** folder shortcut.
4. **If macOS shows `"Klipboard" Not Opened`** (because this open-source build is ad-hoc signed rather than notarized with a paid Apple Developer ID):
   - **Fastest fix (Terminal)**:
     ```bash
     xattr -cr /Applications/Klipboard.app && open /Applications/Klipboard.app
     ```
   - **No-Terminal fix (System Settings)**:
     1. Click **Done** on the popup (do **not** click *Move to Trash*).
     2. Open **System Settings → Privacy & Security**, scroll down to the **Security** section, and click **Open Anyway** next to *"Klipboard" was blocked to protect your Mac*.
5. Grant permission when prompted (see [Permissions](#permissions)).

### Option 3: Homebrew Cask

```bash
brew install --cask --no-quarantine ./Casks/klipboard.rb
```

### Option 4: Build from Source

Requires macOS 14.0+ and Xcode Command Line Tools (`xcode-select --install`).

```bash
./build-release.sh
```

You can customize the build via environment variables (nothing is hardcoded):

```bash
VERSION=0.1.0 BUNDLE_ID=com.abhishek.Klipboard ARCH=arm64 MIN_MACOS=14.0 ./build-release.sh
```

**Sign with a real certificate** so the Accessibility permission survives rebuilds (ad-hoc builds lose it every time):

```bash
SIGN_IDENTITY="Apple Development" ./build-release.sh
```

A free Apple ID is enough: Xcode → Settings → Accounts → Manage Certificates → **+** → Apple Development. If signing fails with `errSecInternalComponent`, install Apple's [WWDR G3 intermediate certificate](https://www.apple.com/certificateauthority/AppleWWDRCAG3.cer).

## Permissions

Klipboard needs **Accessibility** permission (shown as **Device Control and Data Access** on newer macOS) to paste directly into the active app. Without it, clicking an item still copies it — just press `⌘V` yourself.

1. On first paste, click **Open System Settings** on the prompt.
2. Turn on **Klipboard** under **Privacy & Security → Accessibility** (or **Device Control and Data Access**).
3. Quit Klipboard from the menu bar and open it again.

**Prompt keeps coming back even though Klipboard is switched on?** macOS ties the permission to the app's code signature, so a rebuilt or updated app can stop matching the old entry. Reset it and grant again:

```bash
tccutil reset All com.abhishek.Klipboard
```

## Menu Bar

<p align="center"><img src="docs/screenshot-menu.png" alt="Klipboard menu bar menu" width="470"></p>

| Item | Action |
| :--- | :--- |
| **Open Clipboard History** | Show the floating panel |
| **Shortcut** | Choose `⌥V` or `⌘⇧V` |
| **Launch at Login** | Start Klipboard automatically when you log in (on by default) |
| **Quit Klipboard** | Stop Klipboard until you open it again or next login |

## Keyboard Shortcuts

| Shortcut | Action |
| :--- | :--- |
| **`⌥V`** or **`⌘⇧V`** | Toggle Klipboard floating panel open / closed |
| **`↑` / `↓`** | Navigate clipboard history items |
| **`Return`** or click | Paste selected item into the active app |
| **`⌘Delete`** or **`Fn+Delete`** | Delete selected item from history |
| **`Esc`** | Dismiss floating panel |

## Automated Hosting & Releases

- **GitHub Releases ([`.github/workflows/release.yml`](.github/workflows/release.yml))**: Pushing a version tag (`git tag v0.1.0 && git push origin v0.1.0`) automatically builds `Klipboard-0.1.0.dmg` on macOS and publishes a GitHub Release on [`akai-49/Klipboard`](https://github.com/akai-49/Klipboard).
- **GitHub Pages ([`.github/workflows/pages.yml`](.github/workflows/pages.yml) + [`docs/index.html`](docs/index.html))**: Deploys the static download landing page (`https://akai-49.github.io/Klipboard/`) automatically whenever `main` is pushed.
- **Homebrew Cask ([`Casks/klipboard.rb`](Casks/klipboard.rb))**: Ready-to-use Homebrew Cask definition pointing to the `.dmg` release asset.

## License

Released under the [MIT License](LICENSE). Copyright © 2026 Abhishek Hiremath.
