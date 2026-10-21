# Klipboard for macOS

**Klipboard** is a fast, lightweight native macOS clipboard manager built with Swift and AppKit/SwiftUI. It lives quietly in your menu bar, captures text, rich text (RTF), links, images, files, and colors with near-zero idle CPU/memory overhead, and opens instantly from anywhere via a Spotlight-style floating panel.

---

## Features

- **Instant Global Shortcut**: Press **`⌥V` (Option + V)** or **`⌘⇧V` (Command + Shift + V)** from any app to toggle the floating clipboard history panel.
- **Direct Paste-Back**: Select any item with `↑` / `↓` and press **`Return`** (or click it) to automatically paste it right into your active app.
- **Multi-Format Capture**:
  - Plain text & code snippets
  - Rich text (RTF)
  - URLs & web links
  - Images (automatically downsampled via `ImageIO` to prevent Retina memory spikes)
  - Files & folders (with quick **Reveal in Finder**)
  - Colors (with live hex previewswatch)
- **Pin, Favorite & Search**: Real-time instant search across text and source app names, plus pinning (`Pin`) and starring (`Favorite`) so important clips are never auto-trimmed.
- **Ultra-Low Resource Usage**: Timer-coalesced pasteboard polling, `NSCache`-backed 64px thumbnail downsampling, and zero background animations when idle.

---

## Installation

### Option 1: Drag-and-Drop DMG Installer (Recommended)

1. Download **`Klipboard-0.1.0.dmg`** from the [**Latest Release**](../../releases/latest) (or from [`dist/Klipboard-0.1.0.dmg`](dist/Klipboard-0.1.0.dmg)).
2. Double-click **`Klipboard-0.1.0.dmg`** to mount the installer volume.
3. Drag **`Klipboard.app`** onto the **`Applications`** folder shortcut.
4. Launch **Klipboard** from `/Applications` or Spotlight (`⌘Space`).
   - *First-launch note (ad-hoc signed build)*: If macOS Gatekeeper prompts on first open, run:
     ```bash
     xattr -cr /Applications/Klipboard.app
     ```
     or go to **System Settings → Privacy & Security → Open Anyway**.
   - Grant **Accessibility** permission when prompted so Klipboard can listen for global shortcuts and paste directly into your active window.

### Option 2: Homebrew Cask

```bash
brew install --cask --no-quarantine ./Casks/klipboard.rb
```

### Option 3: Build from Source

Requires macOS 14.0+ and Xcode Command Line Tools (`xcode-select --install`).

```bash
./build-release.sh
```

This compiles a release binary (`-O -whole-module-optimization`), signs `Klipboard.app`, and packages the drag-and-drop installer at `dist/Klipboard-0.1.0.dmg`.

---

## Keyboard Shortcuts

| Shortcut | Action |
| :--- | :--- |
| **`⌥V`** or **`⌘⇧V`** | Toggle Klipboard floating panel open / closed |
| **`↑` / `↓`** | Navigate clipboard history items |
| **`Return`** | Paste selected item into the active app |
| **`⌘Delete`** or **`Fn+Delete`** | Delete selected item from history |
| **`Esc`** | Dismiss floating panel |

---

## Automated Hosting & Releases

- **GitHub Releases (`.github/workflows/release.yml`)**: Pushing a version tag (`git tag v0.1.0 && git push origin v0.1.0`) automatically builds `Klipboard-0.1.0.dmg` on macOS and publishes a GitHub Release.
- **GitHub Pages (`.github/workflows/pages.yml` + `docs/index.html`)**: Deploys the static download landing page in `docs/` automatically whenever `main` is pushed.
- **Homebrew Cask (`Casks/klipboard.rb`)**: Ready-to-use Homebrew Cask definition pointing to the `.dmg` release asset.

---

## License

Released under the [MIT License](LICENSE). Copyright © 2026 Abhishek Hiremath.
