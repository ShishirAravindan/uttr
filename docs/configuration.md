# Configuration

uttr uses a YAML configuration file stored at:

```
~/Library/Application Support/uttr/settings.yaml
```

Edit settings via the app's Settings UI or by editing the YAML directly.
Quit the app before editing the file, then relaunch to load it. The app does not
watch the YAML for external changes. Debug and Release share this file.

## Settings Reference

### Provider

```yaml
provider: "fluidaudio.parakeet.v3"
```

| Value | Description |
|-------|-------------|
| `fluidaudio.parakeet.v3` | Parakeet v3 — multilingual (recommended) |
| `fluidaudio.parakeet.v2` | Parakeet v2 — English only |

### Fluid Audio

```yaml
fluid_audio:
  model_version: "v3"   # v2 or v3
```

This field is retained in the serialized configuration. The provider factory uses
`provider` to select the model; `fluid_audio.model_version` does not override it.
Changing the provider in Settings updates `provider`, but does not synchronize
this field. Keep them consistent when editing YAML for clarity.

### Audio

```yaml
audio:
  input_device_uid: null   # null = follow the system default input
```

Pins recording to a specific microphone. The value is a Core Audio **device UID** — stable across reboots and replugs, unlike the numeric device ID.

Pick the device from Settings → Audio → Input device rather than writing the UID by hand. `null` (or omitting the `audio` block entirely) records from whatever macOS has set as the system default input.

If the pinned device isn't connected when you start a recording, uttr falls back to the system default and notes it in the log.

### Hotkey

```yaml
hotkey:
  key_code: 37           # macOS key code (37 = L)
  modifiers: ["option"]  # command, option, control, shift
```

Common key codes: `37` = L, `0` = A, `49` = Space, `36` = Return.

Use the Settings UI to record a new hotkey — it sets these values automatically.

### Selection Shortcuts

```yaml
speak_hotkey:            # read the selection aloud
  key_code: 15           # 15 = R
  modifiers: ["option"]
cleanup_hotkey:          # clean up the selection and replace it
  key_code: 8            # 8 = C
  modifiers: ["option"]
```

Omitted blocks use these defaults. Settings rejects a shortcut that another uttr
action already uses.

### Cleanup

```yaml
cleanup:
  prompt: "Clean up this text. Keep all of the words and the meaning. ..."
  clean_dictation: false
```

`prompt` is the instruction the cleanup shortcut and dictation cleanup follow. An
empty prompt restores the default. uttr adds one fixed line after it, telling the
model to treat the selected text only as text to clean.

`clean_dictation` cleans dictation after transcription and before pasting. History
then records both the transcript and the cleaned text. If cleanup is unavailable or
fails, the transcript is pasted unchanged.

Cleanup needs Apple Intelligence on macOS 26 or later.

## Full Example

```yaml
provider: "fluidaudio.parakeet.v3"
fluid_audio:
  model_version: "v3"
hotkey:
  key_code: 37
  modifiers: ["option"]
audio:
  input_device_uid: null
speak_hotkey:
  key_code: 15
  modifiers: ["option"]
cleanup_hotkey:
  key_code: 8
  modifiers: ["option"]
cleanup:
  prompt: "Clean up this text. Keep all of the words and the meaning. ..."
  clean_dictation: false
```
