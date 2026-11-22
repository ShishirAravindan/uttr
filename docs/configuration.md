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

Pick the device from Settings → Speech to Text → Input device rather than writing the UID by hand. `null` (or omitting the `audio` block entirely) records from whatever macOS has set as the system default input.

If the pinned device isn't connected when you start a recording, uttr falls back to the system default and notes it in the log.

### Hotkey

```yaml
hotkey:
  key_code: 37           # macOS key code (37 = L)
  modifiers: ["option"]  # command, option, control, shift
```

Common key codes: `37` = L, `0` = A, `49` = Space, `36` = Return.

The read-aloud shortcut uses the same shape under its own key (default `⌥R`, key
code 15):

```yaml
read_aloud_hotkey:
  key_code: 15
  modifiers: ["option"]
cleanup_hotkey:          # clean up the selection, default ⌥C (key code 8)
  key_code: 8
  modifiers: ["option"]
```

Use the Shortcut row in each pane of Settings (Speech to Text, Text to Speech, Instruct) to record a new hotkey — it sets these values automatically.
A shortcut needs at least one of command, option or control, and Settings rejects
one that another action already uses. If another app already holds a shortcut,
uttr logs the failure and registers the rest.

### History

```yaml
history:
  max_entries: 5   # entries kept in history, 1 or more
```

Raising the limit keeps more entries from then on. Lowering it removes the oldest
entries, and their recordings, right away. Settings warns above 50 because each
entry keeps its recording on disk.

### Cleanup

```yaml
cleanup:
  prompt: "Fix spelling and punctuation only."   # omit to use the built-in prompt
  clean_dictation: false                          # clean dictation before pasting
```

Settings → Instruct edits the prompt; Restore default removes the key. The output
checks in [Cleanup](cleanup.md#output-checks) apply whatever the prompt says.

### Read Aloud

```yaml
read_aloud:
  voice: "kokoro"            # system, kokoro, or an expressive preset (below)
  speed: 1.0                 # 0.75–1.5, every voice, pitch preserved
  idle_unload_minutes: 5     # drop the expressive model from memory after this long idle
  sentences_per_chunk: 3     # 1–3; fewer starts sooner, more gives the model context
  models:                    # values changed per preset; anything missing uses its default
    mlx.qwen3-voicedesign:
      description: "A gravelly old sea captain telling a story by the fire."
      temperature: 0.9
    mlx.chatterbox:
      exaggeration: 0.8
      cfg_weight: 0.3
      consistent_voice: false
```

Expressive presets: `mlx.chatterbox-turbo`, `mlx.chatterbox`,
`mlx.qwen3-voicedesign`, `mlx.qwen3-customvoice`, `mlx.orpheus`, `mlx.marvis`.
Per-preset keys are the parameter IDs that preset declares:

| Key | Presets | Value |
|-----|---------|-------|
| `speaker` | Qwen3 CustomVoice, Orpheus, Marvis | One of the preset's speakers |
| `description` | Qwen3 VoiceDesign | Natural-language voice description |
| `style` | Qwen3 CustomVoice | Style direction |
| `exaggeration`, `cfg_weight` | Chatterbox | 0–1 |
| `temperature` | all | 0.1–1.3 |
| `top_p`, `repetition_penalty` | Qwen3, Orpheus | 0.5–1.0; 1.0–2.0 |
| `consistent_voice` | all | `true` (default) or `false` |

A key a preset doesn't declare is ignored, and an unknown voice falls back to
Kokoro. Choosing a preset in Settings downloads it; see [Read Aloud](read-aloud.md).

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
history:
  max_entries: 5
read_aloud_hotkey:
  key_code: 15
  modifiers: ["option"]
cleanup_hotkey:
  key_code: 8
  modifiers: ["option"]
read_aloud:
  voice: "kokoro"
  speed: 1.0
  idle_unload_minutes: 5
```
