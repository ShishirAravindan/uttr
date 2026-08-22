# Configuration

uttr uses a YAML configuration file stored at:

```
~/Library/Application Support/uttr/settings.yaml
```

Edit settings via the app's Settings UI or by editing the YAML directly.

## Settings Reference

### Provider

```yaml
provider: "fluidaudio.parakeet.v3"
```

| Value | Description |
|-------|-------------|
| `fluidaudio.parakeet.v3` | Parakeet v3 — multilingual (recommended) |
| `fluidaudio.parakeet.v2` | Parakeet v2 — English only, faster |

### Fluid Audio

```yaml
fluid_audio:
  model_version: "v3"   # v2 or v3
```

This mirrors the `provider` selection. Changing the provider in Settings updates both fields.

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
```
