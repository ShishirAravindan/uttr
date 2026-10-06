# Architecture

## Overview

uttr is a single-tier Swift app. All transcription happens in-process via FluidAudio — there is no server, no Python, and no network communication after the initial model download.

## Transcribe Flow

Hotkey → `TranscriptionSession` → `AudioRecorder` writes WAV → `FluidAudioProvider.transcribe()` → `TranscriptCleanup` → `PasteManager` pastes at cursor

`TranscriptionSession` owns the workflow on the main actor. Its state moves through
loading, idle, capturing, transcribing, cleaning, and inserting; a failed model preparation
leaves it unavailable. The popover and menu-bar icon reflect that state. A new
recording waits until transcription, cleanup, and paste finish.

Provider changes during an utterance are queued until insertion completes, with
the latest request taking precedence. Superseded preparation results are ignored,
and provider teardown waits for outstanding preparation or inference. Shutdown
stops capture and invalidates late results; app quit remains immediate.

## Components

| File | Responsibility |
|------|---------------|
| `uttr.swift` | App lifecycle, windows, hotkey wiring, and session presentation |
| `TranscriptionSession.swift` | Recording-to-insertion state, task ownership, and provider lifecycle |
| `Cleanup/TranscriptCleanup.swift` | Cleanup deadline, output checks, and raw-text fallback |
| `Cleanup/AppleCleanupBackend.swift` | On-device Foundation Models with fresh per-utterance context |
| `AudioRecorder.swift` | AVAudioEngine capture to native-rate WAV files |
| `AudioDeviceManager.swift` | Core Audio input-device enumeration and UID → device ID lookup |
| `HotkeyManager.swift` | Global hotkey registration via Carbon |
| `PasteManager.swift` | Clipboard write + simulated paste |
| `AppPaths.swift` | Shared settings/history and app-owned temporary recording locations |
| `HistoryStore.swift` | Atomic history persistence and legacy migration under a file lock |
| `SettingsManager.swift` | YAML-backed settings (`~/Library/Application Support/uttr/settings.yaml`) |
| `MenuBarIconManager.swift` | Status bar icon states and animations |
| `Transcription/TranscriptionProvider.swift` | Provider contract |
| `Transcription/TranscriptionProviderFactory.swift` | Provider selection from settings |
| `Transcription/FluidAudioProvider.swift` | FluidAudio integration (Parakeet v2/v3) |

## Settings Schema

```yaml
provider: "fluidaudio.parakeet.v3"   # or fluidaudio.parakeet.v2
fluid_audio:
  model_version: "v3"
hotkey:
  key_code: 37
  modifiers: ["option"]
audio:
  input_device_uid: null               # null = system default input
```

## Input Device Selection

`AVAudioEngine` has no device picker — its input node always follows the system default input. uttr overrides it through the HAL unit behind the node (`AUAudioUnit.setDeviceID(_:)`), which is the supported escape hatch on macOS.

Two consequences shape the code:

- **Device IDs are not stable.** Core Audio assigns `AudioDeviceID`s at runtime, so settings persist the device *UID* and `AudioDeviceManager` translates it on every recording. An unplugged device falls back to the system default instead of failing the recording.
- **Input and output share one I/O unit.** Overriding the capture device also moves the output side onto it, and a capture-only device leaves the output bus with an empty format. `AudioRecorder` therefore skips its `mainMixerNode` connection when a pinned device has no output channels and records from a tap-only graph.

## Model Download

FluidAudio downloads and loads the Parakeet model (~600 MB) during provider preparation at launch or after a provider change. Recording is blocked until preparation succeeds. The model is cached and not re-downloaded on subsequent launches.

## Storage lifetime

Post-utterance cleanup and raw-history recovery are described in [cleanup](cleanup.md).

Debug and Release continue to share `~/Library/Application Support/uttr/settings.yaml`
and history. History lives at `~/Library/Application Support/uttr/History/transcription_history.json`;
the newest five entries remain available. On first access, valid legacy history at
`~/Documents/History/transcription_history.json` is merged by entry ID and timestamp,
then written atomically. Only that legacy JSON is removed; its directory is removed
only when empty. Invalid history or a failed migration preserves the source files
and reports the failure. A corrupt legacy file does not block a valid destination;
without a valid destination, corrupt history is preserved and disk updates remain
blocked until the file can be repaired. A fingerprint receipt prevents re-importing
a retained legacy file after history is cleared. Separate current app instances lock
history transactions so updates cannot overwrite another instance's latest entry.
Older versions do not take this lock; quit them before migration. A legacy file
changed since the migration snapshot is left in place for the next migration.

Recordings use UUID filenames inside the user's temporary `uttr/recordings` directory.
AudioRecorder discards failed/interrupted captures and transfers a stopped file to
the session. The session deletes it after inference returns, on success or failure;
cancellation does not delete a file while inference may still read it. Capture is
discarded on shutdown. History's optional audio filename remains metadata, not a
retained audio file or playback feature.

Quit remains immediate. If the process exits while inference is still reading, or
crashes, its temporary file can remain until macOS cleans the temporary directory.
There is no startup sweep: Debug and Release may both be using that directory, and
neither app deletes another active session's audio. A crash-recovery sweep would
need process ownership/leases rather than an age-based deletion rule. Existing
`recording_<timestamp>.wav` files from older builds are not swept either.

Ordinary Homebrew uninstall preserves data. `brew uninstall --zap --cask uttr` opts
into deleting cask-owned paths. The maintained cask is in the separate
`ShishirAravindan/homebrew-tap` repository; its current Application Support stanza
covers the new history location. To cover Release logs too, the tap needs:

```ruby
zap trash: [
  "~/Library/Application Support/uttr",
  "~/Library/Logs/uttr",
]
```

Debug logs stay at `~/Library/Logs/uttr Debug` and belong to the developer install.
Model caches managed by FluidAudio are unchanged.
