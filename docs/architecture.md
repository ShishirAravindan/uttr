# Architecture

## Overview

uttr is a single-tier Swift app. All transcription happens in-process via FluidAudio — there is no server, no Python, and no network communication after the initial model download.

## Transcribe Flow

Hotkey → `TranscriptionSession` → `AudioRecorder` writes WAV → `FluidAudioProvider.transcribe()` → `PasteManager` pastes at cursor

`TranscriptionSession` owns the workflow on the main actor. Its state moves through
loading, idle, capturing, transcribing, and inserting; a failed model preparation
leaves it unavailable. The popover and menu-bar icon reflect that state. A new
recording waits until the current transcription and paste finish.

Provider changes during an utterance are queued until insertion completes, with
the latest request taking precedence. Superseded preparation results are ignored,
and provider teardown waits for outstanding preparation or inference. Shutdown
stops capture and invalidates late results; app quit remains immediate.

## Components

| File | Responsibility |
|------|---------------|
| `uttr.swift` | App lifecycle, windows, hotkey wiring, and session presentation |
| `TranscriptionSession.swift` | Recording-to-insertion state, task ownership, and provider lifecycle |
| `AudioRecorder.swift` | AVAudioEngine capture to native-rate WAV files |
| `AudioDeviceManager.swift` | Core Audio input-device enumeration and UID → device ID lookup |
| `HotkeyManager.swift` | Global hotkey registration via Carbon |
| `PasteManager.swift` | Clipboard write + simulated paste |
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
