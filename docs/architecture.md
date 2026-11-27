# Architecture

uttr is a Swift macOS menu-bar app. FluidAudio runs Parakeet in-process on Apple
Silicon. Model preparation can download files; transcription itself runs locally.

![uttr components: hotkeys send requests to ActionCoordinator, which drives capture and Parakeet, cleanup, selection reading, and read-aloud, delivers through PasteManager, and drives menu-bar feedback from its state](assets/diagrams/architecture.png)

## Recording and Delivery

![Recording flow run by ActionCoordinator: provider preparation, capture, transcription, optional cleanup, history, delivery to the same app or the clipboard, and status feedback](assets/diagrams/recording-flow.png)

`AppDelegate` in `Swift/uttr.swift` creates the components and the
`ActionCoordinator` (`Swift/Coordination/`), which runs the recording-to-paste flow:

1. Launch or a provider change calls `prepare()` to download/load the selected
   model. Recording is blocked until `isProviderReady` is true.
2. The registered hotkey starts `AudioRecorder`. A second invocation stops capture
   and hands back a temporary WAV at the input's native format.
3. A coordinator-owned task calls `FluidAudioProvider.transcribe(audioFileURL:)`.
4. If Clean up dictation is on, the coordinator runs `TextCleanup` with the
   `.dictation` profile, which returns within 2 seconds with either cleaned text
   or the transcript ([Cleanup](cleanup.md)).
5. The coordinator queues a history update and delivers the text. Delivery checks
   that the app in front is still the one the action started in; if not, nothing is
   pasted, the text is left on the clipboard, and the menu-bar icon flashes a clipboard symbol instead of the checkmark. Otherwise `PasteManager` uses the
   clipboard and simulated `Cmd+V` events. The menu-bar icon and sounds report the
   outcome.

## Action Coordination

Dictation, read-aloud (⌥R), and selection cleanup (⌥C, the "instruct" action) all
go through `ActionCoordinator`, a `@MainActor` object that owns one foreground
`ActionState` (idle, capturing, transcribing, cleaning, inserting, reading a
selection, speaking, instructing) and one task per run. `ActionPolicy` decides what
a new request does to the state. It derives the answer from a fixed priority:
dictation (STT) over instructions over read-aloud (TTS). A higher-priority request
replaces the current action, a lower one is ignored, and equal priorities follow
their own rule.

| Current state | Record | ⌥C (instruct) | ⌥R (read aloud) |
|---------------|--------|---------------|-----------------|
| Idle | Start | Start | Start |
| Capturing | Stop | Ignored | Ignored |
| Transcribing, inserting | Start a new recording; the earlier run still pastes | Ignored | Ignored |
| Cleaning dictation | Deliver the transcript now, then record | Ignored | Ignored |
| Reading a selection | Cancel the read, then record | Cancel the read, then clean | Cancel |
| Speaking | Stop speech, then record | Stop speech, then clean | Stop |
| Instructing (reading, cleaning) | Cancel it, then record | Ignored | Ignored |
| Instructing (inserting) | Start; the paste finishes | Ignored | Ignored |

Ignored hotkeys give a brief dip of the menu-bar icon and no sound. A selection read
that was cancelled finishes its clipboard round trip before the next read starts, so
reads never overlap. The icon is derived from the state: it shows recording,
processing, transforming, or speaking, and a finished run flashes its result only
when nothing else is using the icon. A background dictation still cleaning up makes
⌥C ignored. A model that is still loading refuses a recording before anything else
is stopped. On quit the coordinator cancels every run; a transcript that was being
cleaned is saved to history as it was. The hotkey channel carries press and release
events, but only presses are registered today.

Provider switches still tear down and replace the provider in an asynchronous
task owned by `AppDelegate`.

## Components

| File under `Swift/` | Responsibility |
|--------------------|----------------|
| `uttr.swift` | App lifecycle, component wiring, windows |
| `Coordination/ActionPolicy.swift`, `Coordination/ActionCoordinator.swift`, `Coordination/MenuBarFeedback.swift` | Action state, the priority-based policy, run ownership and delivery checks, and the menu-bar/sound feedback driven from state |
| `AudioRecorder.swift` | AVAudioEngine capture to a native-format temporary WAV; interruption reporting |
| `AudioDeviceManager.swift` | Core Audio input enumeration and UID → runtime device ID lookup |
| `HotkeyManager.swift` | Global shortcuts registered per action (recording, read aloud, clean up selection) via Carbon |
| `PasteManager.swift` | Simulated Cmd+V around a clipboard transaction; restores the previous clipboard 0.5 s later |
| `ClipboardTransaction.swift` | Item-level pasteboard snapshot, transient-marked write, restore only if nothing newer was copied |
| `SettingsManager.swift` | YAML persistence, provider/device/hotkey changes |
| `PermissionManager.swift` | Microphone and Accessibility checks, onboarding, permission refresh |
| `HistoryManager.swift` | Recent entries labeled by kind, up to the configured limit; JSON persistence; deletes recordings of removed entries; copy/clear APIs |
| `MenuBarPopoverView.swift` | Menu-bar popover with History, Settings, and Quit buttons, wired through `PopoverViewModel` |
| `SettingsWindowView.swift`, `SettingsTabView.swift`, `HomeTabView.swift` | Settings, permissions, and history UI |
| `MenuBarIconManager.swift`, `NotificationManager.swift` | Status feedback |
| `Transcription/TranscriptionProvider.swift` | Provider protocol and factory |
| `Transcription/FluidAudioProvider.swift` | Parakeet v2/v3 preparation, inference, teardown |
| `Cleanup/TextCleanup.swift`, `Cleanup/CleanupOutputChecks.swift`, `Cleanup/AppleCleanupBackend.swift` | On-device text cleanup with deadlines and output checks. See [Cleanup](cleanup.md). |
| `Cleanup/SelectionCleanup.swift` | The cleanup step of ⌥C; the coordinator reads the selection and delivers the result |
| `Selection/SelectionReader.swift` | Reads the frontmost selection with a Cmd+C round trip, waiting up to about 0.75 s for slow apps and restoring the clipboard unless it changed; used by the coordinator for ⌥R and ⌥C |
| `Speech/SpeechEngine.swift`, `Speech/ReadAloud.swift` | Read-aloud: the `SpeechEngine` protocol with the system voice, and the voice owner that switches voices between reads |
| `Speech/BufferedSpeechEngine.swift`, `Speech/SpeechPipeline.swift` | Shared PCM playback for Kokoro and MLX, including buffering, speed, skip, and completion |
| `Speech/KokoroSpeechSource.swift`, `Speech/MLXSpeechSource.swift` | Backend-specific synthesis and chunking. Kokoro runs its Core ML stages on the Neural Engine or CPU. |
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
resolves FluidAudio and Yams through Swift Package Manager. See
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

The coordinator requests a history update before attempting paste. With dictation
cleanup on, that happens after cleanup; a quit during those 2 seconds saves the
transcript as it was. HistoryManager
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
