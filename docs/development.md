# Development Guide

This guide covers building and developing uttr from source.

## Prerequisites

- **Xcode 15+** — [Download from Mac App Store](https://apps.apple.com/app/xcode/id497799835)
- **macOS 14 (Sonoma)+** — Required for deployment target
- **Apple Silicon** — Required for FluidAudio / Neural Engine

## Repository Structure

```
uttr/
├── Swift/                          # macOS app source
│   ├── uttr.swift                  # App entry point
│   ├── AudioRecorder.swift         # Audio capture
│   ├── HotkeyManager.swift         # Global hotkeys
│   ├── Transcription/              # Provider protocol + implementations
│   └── ...
├── docs/                           # Documentation
├── Casks/uttr.rb                   # Homebrew cask formula
├── uttr.xcodeproj/                 # Xcode project
└── README.md
```

## Building the App

### 1. Clone the Repository

```bash
git clone https://github.com/Rakk301/homebrew-uttr.git
cd homebrew-uttr
```

### 2. Open in Xcode

```bash
open uttr.xcodeproj
```

### 3. Build and Run

- Select the **uttr** scheme
- Press `Cmd+R` to build and run
- Grant permissions when prompted

Or use the build script:

```bash
./build.sh -c Debug
```

### Debug and Release identity

Debug builds produce **uttr Debug.app** with an amber DEV badge on the wordmark icon
(D at smaller sizes). A D beside the menu bar icon and the name in About identify
the running build. `./build.sh -c Debug --open` opens it from the build directory.

Debug uses Xcode's “Sign to Run Locally” (ad-hoc signing), including the complete
app bundle and its Info.plist. The script enables signing for Debug; no developer
certificate or team is required. Release's script signing flags stay unchanged.

Release builds use **uttr.app** and the original wordmark icon. The existing bundle
IDs stay `io.github.Rakk301.uttr.debug` and `io.github.Rakk301.uttr`, so macOS keeps
their permission grants separate. Settings and transcription history are shared;
logs follow the app's bundle name under `~/Library/Logs/`.

Both icons are checked in as static PNGs in `Assets.xcassets/AppIcon.appiconset`
and `Assets.xcassets/AppIconDebug.appiconset`. Update the corresponding asset set
when changing either icon.

## Required Permissions

When running from Xcode, you'll need to grant:

| Permission | Purpose | How to Grant |
|------------|---------|--------------|
| Microphone | Audio recording | Prompt appears, or System Settings → Privacy |
| Accessibility | Global hotkeys, paste | System Settings → Privacy → Accessibility |

Enable **uttr Debug** separately from **uttr**. The Accessibility action opens
System Settings even on repeated requests. If the app is missing from the list,
use the folder action beside the guidance to select the running app in Finder,
then add that app with **+** in System Settings. This works for Xcode, script,
and temporary build locations; it does not assume the app is in `/Applications`.

Ad-hoc signatures identify a particular build, so macOS may require a fresh grant
after rebuilding. For permission continuity across builds, use your own Apple
Development certificate/team in Xcode. Grant the app's permission; granting Xcode
does not replace the app's own approval.

## Debugging

### Swift Logs

Logs appear in Xcode console. Filter by component:

- `[AudioRecorder]` — Recording issues
- `[HotkeyManager]` — Hotkey registration
- `[FluidAudioProvider]` — Transcription issues

### Common Issues

**Hotkey not working:**
- Verify Accessibility permission is granted
- Check another app isn't using the same hotkey

**Transcription fails on first run:**
- The Parakeet model (~600 MB) downloads on first use — wait for completion
- Check network connectivity if download stalls

## Code Style

- One file per component/responsibility
- Use `Logger` for all logging, not `print()`
- Prefer `async/await` for asynchronous operations
- Follow existing patterns in the codebase

## Building for Distribution

```bash
./build.sh -c Release
```

This builds, then installs to `/Applications/uttr.app`. See [Releasing Guide](releasing.md) for the full release process.

## Related Docs

- [Architecture](architecture.md) — How it works internally
- [Configuration](configuration.md) — Settings reference
- [Troubleshooting](troubleshooting.md) — Common issues
