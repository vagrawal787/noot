# Noot

A local-first developer note-taking app for macOS. Quick capture with global hotkeys, fast search, and minimal UI.

## Features

- **Global Hotkeys** - Capture notes from anywhere without switching apps
- **Local-First** - All data stored locally in SQLite, no account required
- **Fast Search** - Full-text search across all notes
- **Minimal UI** - Clean interface that stays out of your way

## Installation

### Direct Download

1. Download the latest `Noot-x.x.x.dmg` from [Releases](../../releases)
2. Open the DMG and drag Noot to Applications
3. Launch Noot from Applications

**First Launch (Security Bypass):**

macOS will show a security warning for apps downloaded outside the App Store:

1. Click "Cancel" on the warning dialog
2. Open **System Settings → Privacy & Security**
3. Scroll down to the Security section
4. Click **"Open Anyway"** next to the Noot message
5. Click "Open" in the confirmation dialog

### Homebrew

```bash
brew tap vagrawal787/noot
brew install --cask noot
```

Then follow the same security bypass steps above.

## Permissions

Noot requires the following permissions to function:

### Accessibility (Required)

For global hotkeys to work system-wide:

1. Open **System Settings → Privacy & Security → Accessibility**
2. Click the **+** button
3. Navigate to Applications and select **Noot**
4. Toggle Noot **ON**

### Screen Recording (Optional)

Only needed if you want to capture screenshots into notes:

1. Open **System Settings → Privacy & Security → Screen Recording**
2. Click the **+** button and add Noot
3. Toggle Noot **ON**

## Hotkeys

| Hotkey | Action |
|--------|--------|
| `Option + Space` | New note |
| `⌘ + Option + Space` | Existing notes |
| `⌘ + F` | Focus search |
| `⌘ + Enter` | Save and close |
| `Escape` | Close without saving |

## Build from Source

Requirements:
- macOS 13.0+
- Xcode 15.0+

```bash
# Clone the repository
git clone https://github.com/yourusername/noot.git
cd noot

# Build with Xcode
xcodebuild -project Noot/Noot.xcodeproj \
    -scheme Noot \
    -configuration Release \
    build

# Or open in Xcode
open Noot/Noot.xcodeproj
```

### Creating a Release Build

```bash
./scripts/build-release.sh 1.0.0
```

This creates `Noot-1.0.0.dmg` ready for distribution.

## Data Location

Notes are stored in:
```
~/Library/Application Support/Noot/noot.db
```

## License

MIT
