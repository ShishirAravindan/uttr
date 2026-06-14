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

uttr re-registers the global hotkey automatically the moment Accessibility is
granted — switching back to the app (or just waiting ~2s) is enough, no restart
required. Open **Settings → Permissions** in the app to see live status. If it
still doesn't work:

1. Open **System Settings → Privacy & Security → Accessibility**
2. Find uttr in the list and make sure it's toggled **on**
3. If it's on but still not working, toggle it **off** then **on** again
4. As a last resort, clear the stale grant and relaunch:
   ```bash
   tccutil reset Accessibility io.github.Rakk301.uttr
   ```

If the app isn't in the list at all, open **Settings → Permissions → Accessibility
→ Grant** in the app to trigger the prompt.

> **Why a grant occasionally won't "stick":** the distributed app is ad-hoc
> signed, so macOS ties the Accessibility grant to an unstable code-signing
> identity. After an app **update** the old grant may no longer match the new
> binary — toggle it off/on (or run the `tccutil reset` above) once. Notarizing
> with a Developer ID certificate removes this entirely (see
> [releasing.md](releasing.md)).

### Microphone permission denied

1. Open **System Settings → Privacy & Security → Microphone**
2. Ensure uttr is toggled **on**
3. If not listed, reset permissions:
   ```bash
   tccutil reset Microphone io.github.Rakk301.uttr
   ```

### "Recording failed" error

- Check another app isn't using the microphone exclusively
- Verify your input device is selected in **System Settings → Sound → Input**
- Try unplugging and reconnecting external microphones

## Transcription Issues

### Menu bar shows a loading icon (`…`) on first launch

This is normal. On first launch uttr downloads the Parakeet model (~600 MB). The
menu bar icon shows a loading state and recording is held until it's ready — if
you press the hotkey too early you'll hear the error sound and the status reads
"Loading…". Wait for the download to finish; it's cached afterwards and starts instantly.

### Poor accuracy

1. **Speak clearly** — Parakeet works best with clear speech and minimal background noise
2. **Use a better microphone** — Built-in mic works, but an external mic improves results
3. **Switch providers** — Try Parakeet v3 (multilingual) if using v2

### Text not pasting

1. **Check cursor position** — Click where you want text before starting
2. **Check Accessibility permission** — Required for paste simulation
3. **Try a different app** — Some apps block paste simulation

## Log Files

Check logs for detailed error information:

```bash
# App logs
cat ~/Library/Application\ Support/uttr/transcriptions.log

# System logs (if app crashes)
log show --predicate 'process == "uttr"' --last 10m
```

## Reset Everything

If nothing works, reset to defaults:

```bash
rm ~/Library/Application\ Support/uttr/settings.yaml
```

Then restart the app.

## Getting Help

If you're still stuck:

1. Check [existing issues](https://github.com/Rakk301/homebrew-uttr/issues)
2. Open a [new issue](https://github.com/Rakk301/homebrew-uttr/issues/new) with:
   - macOS version
   - Steps to reproduce
   - Relevant log output
