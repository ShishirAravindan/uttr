# Getting Started

This guide walks you through installing and setting up uttr.

## Installation

### Option 1: Homebrew (Recommended)

```bash
brew install --cask ShishirAravindan/tap/uttr
```

No additional dependencies required. See [Homebrew Tap](homebrew-tap.md) for how the tap is published.

### Option 2: Download from Releases

1. Download the latest `.zip` from [GitHub Releases](https://github.com/ShishirAravindan/uttr/releases)
2. Extract and move `uttr.app` to `/Applications`

### Allowing the App (Gatekeeper)

Since the app is not notarized, macOS will block it on first launch:

1. Try to open the app — you'll see a warning
2. Go to **System Settings → Privacy & Security**
3. Scroll down and click **Open Anyway** next to the uttr message
4. Click **Open** in the confirmation dialog

## Required Permissions

On first launch uttr asks for both permissions it needs, back to back:

### Microphone Access

Required for recording your speech. An in-app prompt appears at launch — click
**OK**. You can also grant it manually at **System Settings → Privacy & Security
→ Microphone**.

### Accessibility Access

Required for the global hotkey and pasting text at your cursor. uttr opens
**System Settings → Privacy & Security → Accessibility** — toggle **uttr** on.

> **No restart needed.** As soon as you flip the Accessibility toggle and switch
> back to uttr, the app detects the grant and registers the global hotkey
> automatically. You can confirm both permissions show **Granted** under
> **Settings → Permissions** in the app.

## First Run

1. **Launch the app** — look for the icon in your menu bar
2. **Grant permissions** — approve the Microphone prompt, then toggle uttr on in
   the Accessibility list
3. **Check status** — open **Settings → Permissions** to confirm both are
   **Granted**
4. **Press your hotkey** (default: `⌥L`) to start recording
5. **Speak**, then press the hotkey again to stop

On first launch, uttr downloads the Parakeet model (~600 MB). The menu bar icon
shows a loading state (`…`) while this happens, and recording is held until the
model is ready — if you press the hotkey too early you'll hear the error sound and
the status reads "Loading…". After the first download the model is cached and
starts instantly.

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

## Next Steps

- [Configuration Guide](configuration.md) — All settings explained
- [Troubleshooting](troubleshooting.md) — Common issues and fixes
