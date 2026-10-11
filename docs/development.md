# Development Guide

This guide covers building and developing uttr from source.

## Prerequisites

- **Xcode 16.1 or later** — CI currently builds with 16.1
- **macOS 15.5 or later** — Required to run the app
- **Apple Silicon** — Required for FluidAudio / Neural Engine

Xcode resolves [FluidAudio](https://github.com/FluidInference/FluidAudio) and
[Yams](https://github.com/jpsim/Yams) through Swift Package Manager. The checked-in
`Package.resolved` pins the versions. Building requires access to those packages;
running the app also needs network access for its first model download.

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
├── Tests/LoggerChecks.swift        # Standalone logger checks
├── .github/workflows/              # PR build and release automation
├── uttr.xcodeproj/                 # Xcode project
└── README.md
```

## Building the App

### 1. Clone the Repository

```bash
git clone https://github.com/ShishirAravindan/uttr.git
cd uttr
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

- The Parakeet model (~600 MB) downloads during provider preparation on launch — wait for completion
- Check network connectivity if download stalls

File logs are under `~/Library/Logs/uttr/` for Release and
`~/Library/Logs/uttr Debug/` for Debug. See [Troubleshooting](troubleshooting.md).

## Logger Checks

These checks use a temporary file and do not launch the app:

```bash
swiftc Swift/Logger.swift Tests/LoggerChecks.swift -o /tmp/uttr-logger-checks
/tmp/uttr-logger-checks
```

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

For build verification without replacing an installed app, use Xcode or an
isolated unsigned build:

```bash
xcodebuild -project uttr.xcodeproj -scheme uttr \
  -configuration Release -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /tmp/uttr-docs-build CODE_SIGNING_ALLOWED=NO build
```

Use a fresh temporary derived-data directory for separate verification runs.

## Architecture Diagrams

Create or edit diagrams in [Excalidraw](https://excalidraw.com). Save local working
scenes as `.excalidraw` files under `docs/assets/diagrams/`; Git ignores these
sources. Keep your working scene locally for later edits. A fresh checkout contains
the rendered images only.

Export PNGs into the same directory and reference them directly from Markdown,
for example `![uttr architecture](assets/diagrams/architecture.png)` in
`docs/architecture.md`. Use a light background, readable labels, and alt text that
describes the diagram. Update the image and its explanation together when the
implementation changes.

For local CLI rendering, the [official Excalidraw CLI](https://github.com/excalidraw/cli)
requires Node.js 22+ and an installed Chrome, Chromium, Edge, or Firefox. It renders
local scenes without an account or API key:

```bash
npx --yes @excalidraw/cli@0.2.0 render \
  docs/assets/diagrams/architecture.excalidraw \
  --out docs/assets/diagrams/architecture.png --scale 2 \
  --max-width 4096 --max-height 4096
```

Validate edits ad hoc: check scene JSON, unique element IDs, binding/container
references, and any embedded assets; render and inspect for clipping, overlapping
labels, and ambiguous arrows; then check Markdown image links and ensure sources
remain ignored. Review the diagram against current code. These checks are not
installed as repository scripts or CI jobs.

## Related Docs

- [Architecture](architecture.md) — How it works internally
- [Configuration](configuration.md) — Settings reference
- [Troubleshooting](troubleshooting.md) — Common issues
