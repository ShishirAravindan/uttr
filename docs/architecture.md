# Architecture

## Overview

uttr is a single-tier Swift app. All transcription happens in-process via FluidAudio — there is no server, no Python, and no network communication after the initial model download.

## Transcribe Flow

Hotkey → `AudioRecorder` writes WAV → `FluidAudioProvider.transcribe()` → `PasteManager` pastes at cursor

## Components

| File | Responsibility |
|------|---------------|
| `uttr.swift` | App lifecycle, hotkey wiring, provider orchestration |
| `AudioRecorder.swift` | AVAudioEngine capture (16 kHz mono WAV) |
| `AudioDeviceManager.swift` | Core Audio input-device enumeration and UID → device ID lookup |
| `HotkeyManager.swift` | Global hotkey registration via Carbon |
| `PasteManager.swift` | Clipboard write + simulated paste |
| `SettingsManager.swift` | YAML-backed settings (`~/Library/Application Support/uttr/settings.yaml`) |
| `MenuBarIconManager.swift` | Status bar icon states and animations |
| `Transcription/TranscriptionProvider.swift` | `TranscriptionProvider` protocol + factory |
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
- **Input and output share one I/O unit.** Overriding the capture device also moves the output side onto it, and a capture-only device leaves the output bus with an empty format. `AudioRecorder` therefore skips its `mainMixerNode` connection when a device is pinned and records from a tap-only graph.

## Model Download

FluidAudio downloads the Parakeet model (~600 MB) on the first `transcribe()` call. The model is cached in the system's ML model store and not re-downloaded on subsequent launches.
