# Klipboard for macOS

**Klipboard** is a fast, lightweight native macOS clipboard manager built with Swift and AppKit/SwiftUI. It lives quietly in your menu bar, captures text, rich text (RTF), links, images, files, and colors with near-zero idle CPU/memory overhead, and opens instantly from anywhere via a Spotlight-style floating panel.

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
- **Pin, Favorite & Search**: Real-time instant search across text and source app names, plus pinning (`Pin`) and starring (`Favorite`) so important clips are never auto-trimmed.
- **Ultra-Low Resource Usage**: Timer-coalesced pasteboard polling, `NSCache`-backed 64px thumbnail downsampling, and zero background animations when idle.

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
5. Grant **Accessibility** permission when prompted so Klipboard can listen for global shortcuts and paste directly into your active window.

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

## Keyboard Shortcuts

| Shortcut | Action |
| :--- | :--- |
| **`⌥V`** or **`⌘⇧V`** | Toggle Klipboard floating panel open / closed |
| **`↑` / `↓`** | Navigate clipboard history items |
| **`Return`** | Paste selected item into the active app |
| **`⌘Delete`** or **`Fn+Delete`** | Delete selected item from history |
| **`Esc`** | Dismiss floating panel |

## Automated Hosting & Releases

- **GitHub Releases ([`.github/workflows/release.yml`](.github/workflows/release.yml))**: Pushing a version tag (`git tag v0.1.0 && git push origin v0.1.0`) automatically builds `Klipboard-0.1.0.dmg` on macOS and publishes a GitHub Release on [`akai-49/Klipboard`](https://github.com/akai-49/Klipboard).
- **GitHub Pages ([`.github/workflows/pages.yml`](.github/workflows/pages.yml) + [`docs/index.html`](docs/index.html))**: Deploys the static download landing page (`https://akai-49.github.io/Klipboard/`) automatically whenever `main` is pushed.
- **Homebrew Cask ([`Casks/klipboard.rb`](Casks/klipboard.rb))**: Ready-to-use Homebrew Cask definition pointing to the `.dmg` release asset.

## License

Released under the [MIT License](LICENSE). Copyright © 2026 Abhishek Hiremath.
