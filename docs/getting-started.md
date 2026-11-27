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

### Read Aloud

Select text in any app and press `⌥R` to hear it. Press `⌥R` again to stop. The
menu-bar icon shows a speaker while it reads, and History keeps what was read.
uttr reads the selection by copying it and then restores your clipboard (every
item and format, unless you copied something new meanwhile), so it
needs the same Accessibility permission as pasting. Dictation comes first, then
`⌥C`, then read-aloud: starting a recording or `⌥C` stops speech, and a shortcut
that can't run right now is ignored with a brief dip of the menu-bar icon.

While a read is active, click the menu-bar icon to see its state, stop it, or skip
to the next section when the voice supports skipping. Settings → Read Aloud
saves one playback speed across voices and app launches. If the System voice is
already speaking, a speed change takes effect on the next read.

**Settings → Text to Speech** lets you choose Kokoro, the macOS System voice,
or one of six expressive voices. Expressive voices use local models. Select a
voice and click **Download** to get its files. The first read with Kokoro
prepares its FluidAudio model, downloading about 320 MB if needed.

If the chosen voice is preparing, the read waits and the menu bar displays its
loading indicator. Press `⌥R` again to cancel the read. If an expressive voice
still needs a download or preparation fails, System reads that selection and
your voice choice stays selected for the next read.

### Clean Up a Selection

Select text in any app and press `⌥C`. uttr cleans it with Apple's on-device
model and pastes the result over the selection: spelling, punctuation and
capitalization are fixed and fillers like "um" removed, keeping your words and
meaning. If the cleanup would lose content (a number, a negation, a question),
times out after 10 seconds, or can't run, the selection is left as it was and a
notification says why. If you switch to another app before the cleaned text is
ready, it is not pasted; it is left on the clipboard instead. History keeps the
cleaned text. Cleanup needs Apple
Intelligence on macOS 26 or later; Settings → Cleanup edits the prompt.

### Clean Up Dictation

Settings → Cleanup → **Clean up dictation** (off by default) cleans each
dictation with the same prompt before pasting it. It adds up to 2 seconds; if
cleanup can't finish or would lose content, the transcript is pasted as it was.
The history card shows the cleaned text, with the original transcription under
a disclosure.

### Settings

Access via menu bar icon → Settings:

| Setting | Description |
|---------|-------------|
| **Provider** | Parakeet v3 (multilingual) or v2 (English only) |
| **Shortcuts** | Click the pencil next to a shortcut, then press the new one. It needs ⌘, ⌥ or ⌃; Esc cancels. Shortcuts pause while you choose. |
| **Input device** | Use the system default microphone or pin a specific device |

### History

Open History from the menu-bar popover to review recent entries and copy one
again. Use it to recover text if automatic insertion fails. Each card shows what
produced it. Settings → History sets how many entries are kept (default 5);
lowering it removes the oldest entries and their recordings. Debug and Release
share this history and the settings file.

## Next Steps

- [Configuration Guide](configuration.md) — All settings explained
- [Troubleshooting](troubleshooting.md) — Common issues and fixes
