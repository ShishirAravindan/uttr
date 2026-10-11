# Troubleshooting

Common issues and solutions for uttr.

## Installation Issues

### "App can't be opened because Apple cannot check it for malicious software"

The app is not notarized. To open it:

1. Go to **System Settings → Privacy & Security**
2. Scroll down to find the message about uttr
3. Click **Open Anyway**
4. Click **Open** in the confirmation dialog

## Permission Issues

### Global hotkey not working

1. Open **System Settings → Privacy & Security → Accessibility**
2. Find uttr in the list
3. Toggle it **off**, then **on** again
4. Restart the app

Use Settings → Permissions to request access again. The Accessibility action opens
System Settings even after the one-time prompt has been dismissed. If the app is
missing from the list, use the folder action beside the guidance to reveal the
running app in Finder, then add it with **+**. The app refreshes its permissions
and re-registers the hotkey when access is granted.

Debug builds appear as **uttr Debug**, with separate grants from Release. A local
ad-hoc rebuild may need a fresh grant; see [Development](development.md#required-permissions).

### Microphone permission denied

1. Open **System Settings → Privacy & Security → Microphone**
2. Ensure uttr is toggled **on**
3. If not listed, reset permissions:
   ```bash
   tccutil reset Microphone io.github.Rakk301.uttr
   ```

### "Recording failed" error

- Check another app isn't using the microphone exclusively
- Check Settings → Audio → Input device. A pinned microphone overrides the system default.
- Try unplugging and reconnecting external microphones

If a pinned device is absent before recording, uttr falls back to the system
default. A device that stops during capture discards that recording and reports
an error. For a Bluetooth device that repeatedly stops, try the system default
or another microphone and include the device details with your report.

## Transcription Issues

### Model stays loading

The selected Parakeet model downloads and loads during provider preparation on
launch, and again when switching providers. Its first download is roughly 600 MB.
Recording is blocked until preparation succeeds. Check network access and the
FluidAudio log entries if loading fails; cached models are reused on later launches.

### Poor accuracy

1. **Speak clearly** — Parakeet works best with clear speech and minimal background noise
2. **Use a better microphone** — Built-in mic works, but an external mic improves results
3. **Switch providers** — Try Parakeet v3 (multilingual) if using v2

### Text not pasting

1. **Check cursor position** — Click where you want text before starting
2. **Check Accessibility permission** — Required for paste simulation
3. **Try a different app** — Some apps block paste simulation

Open History from the menu-bar popover to recover and copy the transcription. The
app requests a history update even when the paste attempt fails.

## Log Files

Check logs for detailed error information:

```bash
# App logs
tail -n 100 "$HOME/Library/Logs/uttr/transcriptions.log"

# Debug app logs
tail -n 100 "$HOME/Library/Logs/uttr Debug/transcriptions.log"

# System logs (if app crashes)
log show --predicate 'process == "uttr"' --last 10m
```

## Reset Settings

Quit both Debug and Release, then move the shared settings file aside:

```bash
mv "$HOME/Library/Application Support/uttr/settings.yaml" \
   "$HOME/Library/Application Support/uttr/settings.yaml.bak"
```

Then restart the app to recreate defaults. This resets configuration; history
and downloaded models remain. History is currently stored at
`~/Documents/History/transcription_history.json` and is shared by both builds.

## Getting Help

If you're still stuck:

1. Check [existing issues](https://github.com/ShishirAravindan/uttr/issues)
2. Open a [new issue](https://github.com/ShishirAravindan/uttr/issues/new) with:
   - macOS version
   - Steps to reproduce
   - Relevant log output

Logs include dictated text. Remove private content before attaching them.
