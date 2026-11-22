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

Select text in any app and press `⌥R` to hear it, or use the speaker button in
the menu-bar popover. Press `⌥R` again to stop. While it reads, the menu-bar
speaker's waves move, and the popover shows the sentence being read with pause,
skip, and stop. History keeps what was read.
uttr reads the selection by copying it and then restores your clipboard, so it
needs the same Accessibility permission as pasting. Read-aloud is ignored while
recording, and starting a recording stops it.

The first `⌥R` after each launch also starts preparing the Kokoro voice in the
background. The very first time, that downloads about 320 MB of Kokoro models
through FluidAudio and compiles them for the Neural Engine; later launches load
them from the cache. Until Kokoro is ready, or if it fails to load, the macOS
system voice reads instead, so that first read uses the system voice. A voice
that becomes ready mid-sentence takes over after the current read-aloud. If you
never use read-aloud, uttr never downloads or loads Kokoro.

For reading with expression, choose an expressive voice in Settings → Text to
Speech: speech-LLMs such as Chatterbox, Qwen3-TTS, Orpheus, and Marvis run inside
uttr on the GPU and take their tone from the text. Choosing one downloads the
model (0.6–4.3 GB); nothing else is installed. See [Read Aloud](read-aloud.md).

### Clean Up a Selection

Select text in any app and press `⌥C`. uttr cleans it with Apple's on-device
model and pastes the result over the selection: spelling, punctuation and
capitalization are fixed and fillers like "um" removed, keeping your words and
meaning. If the cleanup would lose content (a number, a negation, a question),
times out after 10 seconds, or can't run, the selection is left as it was and a
notification says why. History keeps the cleaned text. Cleanup needs Apple
Intelligence on macOS 26 or later; Settings → Instruct edits the prompt.

### Clean Up Dictation

Settings → Speech to Text → **Clean up dictation** (off by default) cleans each
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
produced it. Settings → General → History sets how many entries are kept (default 5);
lowering it removes the oldest entries and their recordings. Debug and Release
share this history and the settings file.

## Next Steps

- [Configuration Guide](configuration.md) — All settings explained
- [Read Aloud](read-aloud.md) — Voices, expressive models, and how read-aloud works
- [Troubleshooting](troubleshooting.md) — Common issues and fixes
