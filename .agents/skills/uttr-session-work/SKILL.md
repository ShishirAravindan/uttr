---
name: uttr-session-work
description: Implement or refactor uttr recording, transcription, delivery, and session lifecycle with controlled asynchronous validation. Use for workflow changes, including cleanup or automatic stopping; UI-only styling and documentation edits use the shared AGENTS.md guidance.
---

# Session work in uttr

Read [AGENTS.md](../../../AGENTS.md) for product and review conventions and
[architecture](../../../docs/architecture.md) for the component map. References
here are relative to the skill folder.

## Ownership and behavior

Start from the actual recording-to-paste path. Keep state transitions and UI
projections on the main actor. AudioRecorder owns the capture graph; the provider
owns inference; PasteManager owns platform delivery. TranscriptionSession owns
when those operations run, their task lifetime, and recovery. AppDelegate wires
system events and presents results.

One utterance runs at a time. Hotkey presses during transcription, cleanup, or
insertion must not start another capture. Provider changes during an utterance take effect after
that utterance finishes. A newer provider request supersedes an older preparation;
teardown waits for outstanding use, and stale completions cannot affect state.
Shutdown stops capture and prevents late results from being inserted.

Cleanup runs between ASR and one insertion; preserve the original transcript for
recovery. Its deadline must settle delivery without waiting for an uncooperative
model to stop. Keep that generation owned, prevent overlapping model requests,
and discard late results. Read [cleanup](../../../docs/cleanup.md) for the editing
contract, fallbacks, and on-device evaluation.

These boundaries are the foundation for future VAD, not authorization to build it.
Read the relevant design-notes essay from that branch when making a product change. Logger races, storage migration, clipboard restore,
and Bluetooth device behavior need their own focused changes.

## Validation

Use controlled recorder, provider, and paste implementations for session tests.
Suspend asynchronous work deliberately to test busy input, superseded preparation,
provider switching, and shutdown. Check externally meaningful outcomes: capture
count, delivered/history text, final state, and teardown after inference ends.
Also cover start/stop failure, interruption, preparation/transcription failure,
and delayed paste completion. Cleanup changes also need deadline, cancellation,
raw fallback, and original-history coverage. Evaluate prompt/backend changes with
the synthetic corpus and review meaning, not just exact-match scores. Avoid loading
models or touching the user's audio, history, clipboard, or permission grants in unit
tests.

Build Debug and Release with Xcode or `xcodebuild`, project `uttr.xcodeproj`,
scheme `uttr`, a temporary derived-data path, and `CODE_SIGNING_ALLOWED=NO`.
Run the hostless session test target through the shared scheme when present.
New source files require target membership; test sources belong only to tests.

Do not use `build.sh` merely for verification: its Release path replaces the app
in `/Applications`. Build/test results do not establish live microphone or paste
behavior. Report the exercised paths and remaining manual checks plainly.
