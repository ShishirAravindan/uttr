# Architecture

uttr is a Swift macOS menu-bar app. FluidAudio runs Parakeet in-process on Apple
Silicon. Model preparation can download files; transcription itself runs locally.

![uttr components: AppDelegate coordinates capture, local Parakeet inference, history, paste, and status feedback](assets/diagrams/architecture.png)

## Recording and Delivery

![Recording flow: provider preparation, capture, transcription, queued history, paste attempt, and status feedback](assets/diagrams/recording-flow.png)

`AppDelegate` in `Swift/uttr.swift` creates the components and coordinates the
recording-to-paste flow:

1. Launch or a provider change calls `prepare()` to download/load the selected
   model. Recording is blocked until `isProviderReady` is true.
2. The registered hotkey or popover starts `AudioRecorder`. A second invocation
   stops capture and hands back a temporary WAV at the input's native format.
3. An asynchronous task calls `FluidAudioProvider.transcribe(audioFileURL:)`.
4. On the main actor, if Clean up dictation is on, AppDelegate first runs
   `TextCleanup` with the `.dictation` profile, which returns within 2 seconds
   with either cleaned text or the transcript ([Cleanup](cleanup.md)).
5. AppDelegate queues a history update and calls `PasteManager`. Paste uses the
   clipboard and simulated `Cmd+V` events; success/error feedback updates the
   menu-bar icon and notifications.

The recording flag is cleared before transcription starts. The current app does
not serialize the entire capture/transcription/paste flow or keep its asynchronous
tasks in a separate session owner. Provider switches tear down and replace the
provider in an asynchronous task. Changes to these lifetimes need explicit review
of busy input, provider switching, delayed callbacks, and quit behavior.

## Components

| File under `Swift/` | Responsibility |
|--------------------|----------------|
| `uttr.swift` | App lifecycle, component wiring, recording/transcription orchestration, windows |
| `AudioRecorder.swift` | AVAudioEngine capture to a native-format temporary WAV; interruption reporting |
| `AudioDeviceManager.swift` | Core Audio input enumeration and UID → runtime device ID lookup |
| `HotkeyManager.swift` | Global shortcuts registered per action (recording, read aloud, clean up selection) via Carbon |
| `PasteManager.swift` | Clipboard write, simulated paste, delayed restoration of previous plain text |
| `SettingsManager.swift` | YAML persistence, provider/device/hotkey changes |
| `PermissionManager.swift` | Microphone and Accessibility checks, onboarding, permission refresh |
| `HistoryManager.swift` | Recent entries labeled by kind, up to the configured limit; JSON persistence; deletes recordings of removed entries; copy/clear APIs |
| `MenuBarPopoverView.swift` | Recording and read-aloud controls, with the sentence being read, through `PopoverViewModel` |
| `SettingsWindowView.swift`, `SettingsTabView.swift`, `HomeTabView.swift` | Settings panes (General, Speech to Text, Text to Speech, Instruct) and the history window |
| `MenuBarIconManager.swift`, `NotificationManager.swift` | Status feedback |
| `Transcription/TranscriptionProvider.swift` | Provider protocol and factory |
| `Transcription/FluidAudioProvider.swift` | Parakeet v2/v3 preparation, inference, teardown |
| `Cleanup/TextCleanup.swift`, `Cleanup/CleanupOutputChecks.swift`, `Cleanup/AppleCleanupBackend.swift` | On-device text cleanup with deadlines and output checks. See [Cleanup](cleanup.md). |
| `Cleanup/SelectionCleanup.swift` | ⌥C: cleans the frontmost selection and pastes over it, or reports why it didn't |
| `Selection/SelectionReader.swift` | Reads the frontmost selection with a Cmd+C round trip, restoring the clipboard |
| `Speech/SpeechEngine.swift`, `Speech/ReadAloud.swift`, `Speech/SystemSpeechEngine.swift` | Read-aloud: the `SpeechEngine` protocol, the ⌥R toggle that records a history entry, read-aloud state with pause/skip, voice switches between reads, and the system voice |
| `Speech/SpeechPipeline.swift`, `Speech/SpeechAudioPlayer.swift`, `Speech/SpeechChunks.swift` | Chunked synthesis that stays two chunks ahead of playback, gapless playback with pitch-preserving speed, sentence splitting and grouping |
| `Speech/KokoroSpeechEngine.swift` | FluidAudio's Kokoro voice, with every Core ML stage on the Neural Engine or CPU |
| `Speech/MLXSpeechEngine.swift`, `Speech/TTSModelHost.swift`, `Speech/MLXAudioBackend.swift`, `Speech/SpeechModels.swift` | Expressive speech-LLM voices run in-process on the GPU by mlx-audio-swift; the model loads on demand and unloads when idle; presets declare their settings dials as data. See [Read Aloud](read-aloud.md). |
| `Speech/ReadAloudVoices.swift`, `TextToSpeechSettingsView.swift` | Voice selection, model downloads and removal; the Text to Speech settings pane |
| `Logger.swift` | Shared locked writer for component logs |

## Input Device Selection

Settings persist a Core Audio **device UID**, which `AudioDeviceManager` translates
to a runtime device ID for each recording. A missing pinned device falls back to
the system default. A device that stops mid-recording causes the capture to be
discarded and an interruption callback to report the error.

`AudioRecorder` builds a fresh engine per recording and sets the input node's HAL
device through `AUAudioUnit.setDeviceID(_:)`. Input and output share an I/O unit.
For a pinned capture-only device whose output format is empty, the recorder skips
the mixer connection and records from the input tap. Devices with a valid output
format keep the mixer connection. The WAV preserves the input's native format;
FluidAudio handles the file for inference.

## Provider and Settings

The default is `fluidaudio.parakeet.v3` (multilingual); v2 is English-only. Xcode
resolves FluidAudio, Yams, and mlx-audio-swift (with mlx-swift and swift-huggingface)
through Swift Package Manager. See
[Configuration](configuration.md) for the YAML schema and model-selection behavior.

`prepare()` calls `AsrModels.downloadAndLoad` and creates the `AsrManager`; the first
download is approximately 600 MB. FluidAudio manages its model cache. `transcribe()`
requires a prepared manager, and `teardown()` calls its cleanup method.

## Local Storage

| Data | Current location and behavior |
|------|-------------------------------|
| Settings | `~/Library/Application Support/uttr/settings.yaml`; shared by Debug and Release |
| History | User Documents directory + `History/transcription_history.json`; the configured number of entries (default 5), each with its kind and, after cleanup, its original text; shared by both builds |
| Release logs | `~/Library/Logs/uttr/transcriptions.log` |
| Debug logs | `~/Library/Logs/uttr Debug/transcriptions.log` |
| Recordings | macOS temporary directory; filenames include a recording timestamp. Deleted when their entry leaves history. |
| Kokoro voice models | FluidAudio's cache under `~/.cache/fluidaudio/Models/`, about 320 MB; downloaded the first time ⌥R is used, loaded on the first ⌥R of each launch |
| Expressive voice models | mlx-audio-swift's folder in the Hugging Face cache, `~/.cache/huggingface/hub/mlx-audio/<org>_<name>`; downloaded when selected in Settings, removable in Settings → General → Storage |

AppDelegate requests a history update before attempting paste. With dictation
cleanup on, that happens after cleanup, so a quit during those 2 seconds loses
the transcript. HistoryManager
queues the list update and JSON write on the main queue; persistence is not a
prerequisite for posting paste events. History can recover a failed insertion. Its current writes are not coordinated across simultaneous app
instances. A recording is deleted when its entry is trimmed or history is cleared,
and right away when transcription fails. Discarded interrupted captures are
removed by the recorder. macOS may also purge old files from the temporary
directory on its own.

Debug and Release use separate bundle IDs and permission grants. Their shared
settings/history and separate log directories are described in
[Development](development.md). The [Releasing Guide](releasing.md) covers packaging
and the separate Homebrew tap.
