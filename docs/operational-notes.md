# Operational Notes

Working backlog and the reasoning behind it. The design arguments this rests on live in [`design-notes/`](design-notes/) — this file is the operational shadow of those.

Nothing here is committed work. Items are ordered by dependency, not by priority alone.

---

## How we decide whether a feature is worth building

uttr is meant to be opinionated. That means the output of design work is *one default*, not a setting. Five questions get us there; they are derived from the design notes and they are the same five every time.

**1. Which axis does this move, and does it force a move on another?**
The three axes are delimitation (how a span begins and ends), feedback (when the user learns what was heard), and delivery (how text arrives). A feature that moves one axis is cheap and reversible. A feature that moves two is a new mode and needs a much better reason. See `design-notes/axes-and-modes.md` §8 — the axes are coupled in practice, so check for the hidden second move before costing the work.

**2. What does the failure look like, and is it reversible by a keystroke the user already knows?**
If yes, do not design around it. No confirmation, no review step, no guard rail. Guard rails are attention costs charged on every single use to mitigate a failure that costs one ⌘Z. If no — if the failure destroys something the user cannot get back — that is the one case where defensive work is warranted.

**3. What does the library hand us for free, and what does taking it cost elsewhere?**
Free capability is rarely free. The `StreamingEouAsrManager` case below is the worked example: an object that appeared to bundle two features at no extra integration cost turned out to charge for it in transcription quality, on a different axis than the one we were shopping on.

**4. Is the new behaviour predictable enough that the user stops watching it?**
Automation removes a task but can add a monitoring burden. If the user cannot anticipate when an automatic behaviour will fire, they will watch for it, and watching is worse than the action it replaced. Any automatic behaviour needs a legibility story shipped alongside it, not after it.

**5. What is the default, and can we defend having no setting?**
If the honest answer is "it depends on the user," we have not finished the design. A setting is what we ship when we could not decide.

---

## 1. `TranscriptionSession` extraction

**Status:** decided, unblocked, nothing else should land before it.

**Decision:** the session owns the state machine. `AppDelegate` becomes the boundary — app lifecycle, menu bar, windows, wiring — and hands recording concerns off entirely.

**Why.** `AppDelegate.isRecording` is currently the state machine, and the true state is smeared across `isRecording`, `isProviderReady`, `popoverViewModel.isRecording`, and whatever `MenuBarIconManager` happens to be displaying. Four variables kept in agreement by hand, against an icon layer that already models eight states.

This has already caused one production bug, documented in the comment at `Swift/uttr.swift:275`: `isRecording` was cleared only on the success path, so a failed `stopRecording()` left it `true`, and every later hotkey press re-entered `stopRecording()`, hit the same `nil`, and returned. The app was permanently stuck. That is the predictable failure of encoding a multi-state process in a boolean, and every mode we add makes it likelier.

**Shape.** A `SessionState` enum with associated values, replacing the flags:

```swift
enum SessionState {
    case idle
    case capturing(mode: CaptureMode, startedAt: Date)
    case transcribing(audioURL: URL)
    case inserting(text: String)
}
```

Three properties we want out of this. Illegal states stop being representable — "recording and transcribing simultaneously" cannot be written down. Swift's exhaustive `switch` turns adding a fifth case into a compiler-guided walk through every site that needs updating. And state carries its own data, so the duration backstop has somewhere natural to live (today `recordingStartedAt` sits in `AudioRecorder` purely to produce a debug log line).

**Scope.** Pure refactor. No user-visible change. Success criterion is that `AppDelegate` shrinks and no behaviour moves.

---

## 2. Hands-free termination (`VadManager`)

**Status:** direction decided, shape open. Blocked on item 1.

**Target behaviour.** Recording ends on silence rather than on a second keypress. Hotkey toggle remains as the manual path; a hard duration cap backstops both.

**Pipeline.** Fan out from the tap that already exists in `AudioRecorder.handleAudioBuffer` — the file writer stays exactly as it is, so the transcription path is unchanged:

```
tap (native rate, 1024 frames) → accumulate → AudioConverter → 16 kHz
                                            → VadManager.processChunk (4096 samples / 256 ms)
                                            → silence accumulator → stop
```

The buffering step is real work: the tap delivers ~21 ms buffers at the device's native rate (typically 48 kHz, via `input.inputFormat(forBus: 0)`), and `VadManager` wants fixed 256 ms chunks at 16 kHz.

### Aside: why not `StreamingEouAsrManager`

It was the obvious candidate and it was rejected. It does end-of-utterance detection *and* transcription in one object, which looked like strictly more capability for the same integration cost — question 3 above, exactly.

The cost showed up on a different axis. It runs Parakeet EOU at 120M parameters, a separate model download, against the 600M Parakeet TDT v2 in use today. Roughly 5% word error on LibriSpeech test-clean against v2's 1.69% — about three times the errors. Adopting it for delimitation means either accepting a materially worse transcript or running both models and discarding one's output.

What settled it was noticing that its only advantage over `VadManager` is that it *also* emits live text — and we have decided against a live text surface (item 5). Strip that away and it is a worse model doing a job Silero does in about a megabyte with a single purpose.

Worth recording as the canonical instance of the axes not being independent: a question about the feedback axis resolved a model-selection question on the delimitation axis.

### Open questions

These are the decisions that stand between here and writing code, in the order they need answering.

1. **Where does the VAD consumer live?** Inside `AudioRecorder` (it owns the tap, but then it is doing two jobs), or a separate type the session subscribes to. Follows from item 1 — probably the latter, since the session owns state and termination is a state decision.
2. **Does VAD-stop differ from manual stop?** A VAD-terminated recording *knows* its tail is silence. Trim it before transcription, or hand the whole file over unchanged?
3. **What is the threshold, and is it a constant?** Question 5 says we should be able to pick one number and defend it. The honest complication is that the right number differs between a quick burst and long-gap thinking — which is the argument for item 3 below rather than for a slider.
4. **Leading edge.** Same signal can suppress a recording that captured nothing but silence, instead of sending an empty file to the model. Cheap, and it is question 2 applied: an empty paste is not reversible-by-⌘Z in a satisfying way, it is just confusing.
5. **Default on or opt-in?** Question 5. Current lean: on, with the toggle as manual override, no setting.

---

## 3. Hold-to-talk override

**Status:** parked, but specified. Blocked on item 2 (it exists to override VAD).

The long-gap thinking case is the one place VAD termination is actively wrong: pausing to think ends your utterance. A hold gesture is the manual override that says *ignore silence, I am still going.*

**Mechanism.** Add `kEventHotKeyReleased` to the `EventTypeSpec` array at `Swift/HotkeyManager.swift:118`. That is the whole unlock for key-up.

**Constraint that decided this.** We will not install a `CGEvent` tap or an `NSEvent` global keyboard monitor — both deliver every keystroke system-wide, and the trust cost is disqualifying (`design-notes/ambient.md` §4). Carbon is the only route to key-up that observes nothing but our own combination. Consequences we accept: no modifier-only chords (hold-right-⌘), no double-tap gestures. Both require watching the stream.

Note the ordering benefit: because VAD handles the common case, the constraint costs almost nothing. Push-to-talk stopped being the primary answer to delimitation the moment VAD became one.

---

## 4. `PasteManager` clipboard restore

**Status:** ready now, orthogonal to everything, pick up when the time is right.

`Swift/PasteManager.swift:51` restores the previous clipboard on a fixed 500 ms `asyncAfter`. Two failure modes: a target application that reads the pasteboard lazily gets the *restored* content instead of the transcript; and a user who copies something inside that window has their copy silently overwritten with stale content.

The second one destroys data the user cannot recover, which makes it the one item in the codebase that fails question 2 — the exception that defines the rule. Everything else we have decided to let fail.

Polish, but principled polish: the clipboard is user-owned state, and borrowing it invisibly is the difference between a tool that leaves no trace and one whose side effects you have to remember.

---

## 5. Menu bar legibility

**Status:** wanted, mechanism now clear. Blocked on item 2 (it is driven by VAD output).

Automatic termination that the user cannot anticipate is anti-ambient — question 4. If they cannot predict the cutoff, they will watch for it, and watching is the cost we were trying to remove.

**Rejected approach.** Driving the pulse from raw audio amplitude. `MenuBarIconManager.swift:158` uses a `CABasicAnimation` — fire-and-forget Core Animation, 1.0 → 0.45 opacity, autoreversing, 1.1 s. It is not data-driven at all, so amplitude modulation would mean replacing it with per-frame updates: more machinery than the idea is worth.

**Chosen approach.** Drive it from VAD *state*, not amplitude. Speech detected → the normal breathe, unchanged. Silence accumulating → walk the animation's `toValue` floor downward in proportion to progress toward the cutoff, so the icon visibly fades toward extinction as the timer runs and snaps back to full breathe the instant speech resumes.

The user feels the countdown instead of reading one, and it costs one animation property swap per VAD chunk boundary — 256 ms, not per frame. No new surface. This is the general pattern: an ambient interface grows in resolution, not in area.

---

## 6. Unclaimed capability already in the box

Not features yet — capability we are paying for and not using. Worth knowing about before designing anything that would duplicate it.

**`AsrManager` returns more than we keep.** `Swift/Transcription/FluidAudioProvider.swift:53` discards everything but `result.text`. Also available: **confidence** (a basis for flagging a bad transcript rather than silently pasting it) and **token timings** (word-level timestamps, which is what makes a transcript seekable against its audio).

**History has a prerequisite gap.** `TranscriptionEntry` already stores `audioFileName`, but the recording lives in `FileManager.default.temporaryDirectory` and is never deliberately retained — so anything that wants to play audio back needs a retention decision first. Also note `maxEntries = 5`, and that history writes to `~/Documents/History/` while settings live in `~/Library/Application Support/uttr/`. The split is probably unintentional.

**Vestigial state.** `MenuBarIconManager` defines a `.transforming` case and `setTransformingState()` that nothing in the app calls. Evidence of an earlier ambition toward a command/transform mode. Either wire it up or delete it.

---

## Candidate modes, and why they rank where they do

Scored against the five questions. This is the part that should inform the roadmap.

| Mode | Axes moved | Verdict |
|---|---|---|
| **VAD-terminated transcribe** | delimitation only | **Build.** Serves the short-burst case that is uttr's actual centre of gravity. Removes an action rather than adding one. Library hands it over cheaply. Needs item 5 to be a real ambient gain. |
| **Hold-to-talk override** | delimitation only | **Build after.** Exists specifically for long-gap thinking, which is the unformed-thought case — the strongest argument for speech at all. One event type. |
| **Conversation / continuous** | delimitation + feedback | **Defer.** Serves long-form composition, which is not what uttr is aimed at. Depends on VAD anyway. Revisit only if the long-form use case proves real in daily use. |
| **Capture-then-review** | feedback + delivery | **Reject on principle.** Inserts a central, attention-costing step to prevent failures that cost one ⌘Z. Fails question 2 outright. This is the kid-gloves mode. |
| **Retroactive buffer** | delimitation | **Reject on principle.** "Transcribe the last 20 seconds" requires holding the microphone open continuously. The trust cost is disqualifying for the same reason the keystroke tap is — it obliges the user to hold a belief about the app when they are not using it. Appealing idea, wrong product. |
| **Selection-driven transform** | not a mode | **Separate feature.** Needs a language model, not a recognizer. Also introduces a new trust cost (reading selected text). Park until there is a reason. |
| **Alternative delivery** (unicode typing, floating window, clipboard-only) | delivery | **Not pursuing.** If speech is a support function and the keyboard is primary, elaborate delivery makes the support channel more like a primary one — the wrong direction. The one defensible item is `CGEvent` unicode typing as a *compatibility fallback* where ⌘V is mangled (terminals with bracketed paste, some Electron apps), and that is a bug fix, not a mode. Deprioritised: not currently used in a coding context. |

Two things worth noticing about this table. The rubric *rejects* two ideas that sounded good in isolation, which is the main evidence it is doing work rather than ratifying decisions already made. And every item marked **Build** moves exactly one axis — which is the practical form of the argument in `design-notes/axes-and-modes.md`.

---

## Dependency order

```
PasteManager fix ──────────────────── (orthogonal, anytime)

TranscriptionSession ──► VadManager ──► menu bar legibility
                                    └──► hold-to-talk override
```

Only item 4 can be picked up today. Everything else waits on the extraction, and the single question blocking that is where the VAD consumer will eventually live — answered, provisionally, as "not inside `AudioRecorder`."
