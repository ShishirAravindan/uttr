# Getting Started

This guide walks you through installing and setting up uttr.

You need **macOS 15.5 or later** and **Apple Silicon (M1 or later)**.

## Installation

### Option 1: Homebrew (Recommended)

```bash
brew tap ShishirAravindan/tap
brew install --cask uttr
```

No additional dependencies required.

### Option 2: Download from Releases

1. Download `uttr.zip` from [GitHub Releases](https://github.com/ShishirAravindan/uttr/releases)
2. Extract and move `uttr.app` to `/Applications`

### Allowing the App (Gatekeeper)

Since the app is not notarized, macOS will block it on first launch:

1. Try to open the app — you'll see a warning
2. Go to **System Settings → Privacy & Security**
3. Scroll down and click **Open Anyway** next to the uttr message
4. Click **Open** in the confirmation dialog

## Required Permissions

### Microphone Access

Required for recording your speech.

- The app requests microphone access during first-run onboarding
- Or grant manually: **System Settings → Privacy & Security → Microphone**

### Accessibility Access

Required for global hotkeys and pasting text at your cursor.

- The app prompts automatically
- Or grant manually: **System Settings → Privacy & Security → Accessibility**

The app refreshes permission status when you return from System Settings. If it
is missing from the Accessibility list, use the folder action in Settings to reveal
the running app in Finder, then add it with **+** in System Settings. Debug builds
appear as **uttr Debug** and require their own grants.

## First Run

1. **Launch the app** — look for the icon in your menu bar
2. **Grant permissions** — follow the prompts for Microphone and Accessibility
3. **Wait for the model to finish loading** — Settings shows its status
4. **Press your hotkey** (default: `⌥L`) to start recording
5. **Speak**, then press the hotkey again to stop

On launch, uttr prepares the selected Parakeet model. The first preparation
downloads roughly 600 MB; later launches reuse FluidAudio's cached files.
Recording is blocked while the provider is loading. Transcription time depends
on the recording and hardware.

## Using the App

### Basic Workflow

1. Place your cursor where you want text to appear
2. Press the hotkey to **start recording** (menu bar icon changes)
3. Speak clearly into your microphone
4. Press the hotkey again to **stop recording**
5. Transcribed text is automatically pasted at your cursor

### Settings

Access via menu bar icon → Settings:

| Setting | Description |
|---------|-------------|
| **Provider** | Parakeet v3 (multilingual) or v2 (English only) |
| **Hotkey** | Click "Change" to record a new shortcut |
| **Input device** | Use the system default microphone or pin a specific device |

### History

Open History from the menu-bar popover to review the latest five transcriptions
and copy one again. Use it to recover text if automatic insertion fails. Debug and
Release share this history and the settings file.

## Next Steps

- [Configuration Guide](configuration.md) — All settings explained
- [Troubleshooting](troubleshooting.md) — Common issues and fixes
