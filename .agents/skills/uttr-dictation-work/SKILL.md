---
name: uttr-dictation-work
description: Change uttr recording, transcription, paste delivery, or provider lifecycle with validation of asynchronous boundaries. Use for dictation workflow changes, not documentation refreshes or UI-only styling.
---

# Dictation work in uttr

Read [AGENTS.md](../../../AGENTS.md) and [architecture](../../../docs/architecture.md),
then trace the current calls in `Swift/uttr.swift`. AudioRecorder owns capture,
FluidAudioProvider owns inference, PasteManager owns clipboard/key-event delivery,
and AppDelegate wires them together.

## Asynchronous boundaries

The current recording flag ends before inference. Transcription, provider
preparation/switching, and quit teardown use tasks that AppDelegate does not retain.
Paste completion reports event posting before the delayed clipboard restoration.
Do not infer serialization, task cancellation, safe provider handoff, or confirmed
target-app insertion from these callbacks. If changing those guarantees, describe
the before/after behavior and validate the relevant interleavings.

Review start/stop failures and capture interruption; input while loading or
transcribing; provider changes during preparation/inference; delayed paste and icon
callbacks; and quit while work is outstanding. Preserve the user's chosen scope:
device dropout, storage ownership, and clipboard fidelity are separate changes
unless the task includes them.

## Validation

Use controlled recorder/provider/paste substitutes when a change warrants tests.
Suspend work deliberately to expose overlapping input and stale completions. Check
observable outcomes such as capture count, delivered text, history entries, final
UI state, and teardown timing. Keep synthetic checks away from real microphones,
models, user history, clipboard, and permission grants.

Build affected Debug/Release configurations with Xcode or `xcodebuild` using a
temporary derived-data path and `CODE_SIGNING_ALLOWED=NO`. Follow
[Development](../../../docs/development.md) for build commands and the existing
logger check. There is no lifecycle XCTest target in current main; add tests only
when the requested implementation justifies them. Report live capture/inference/
paste checks separately from builds and synthetic checks.
