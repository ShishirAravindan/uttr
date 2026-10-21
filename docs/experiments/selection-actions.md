# Selection actions (experiment)

Throwaway exploration, not shipped behavior. It adds three global hotkeys that act
on the text selected in the frontmost app. They reuse uttr's existing primitives
plus two new ones: a local language model (text → text) and a local voice
(text → audio).

| Hotkey | Action | Pipeline |
|--------|--------|----------|
| ⌥K | Tidy selection | selection → tidy prompt → paste (replaces the selection) |
| ⌥J | Speak selection (press again to stop) | selection → speech |
| ⌥⇧L | Instruct selection | selection + dictated instruction → rewrite → paste |

For **Instruct**, select text and press ⌥⇧L, then say something like "make this
friendlier" or "turn this into bullets". Press ⌥⇧L or ⌥L again to stop. Parakeet
transcribes the instruction, the model rewrites the selection, and the result
replaces it. The other two actions remove the need to copy text first, which is what
the old Python sidecar's ⌥S transform hotkey required.

This was written in a Linux container without Xcode, so it has **not been compiled or
run**. FluidAudio calls were checked against the source of the pinned revision
(0.14.3, `00ea906`). Foundation Models calls follow the pattern that PR #15 builds
with Xcode 26.3.

## Trying it

Debug builds enable the experiment by default. Release builds need it set in
`~/Library/Application Support/uttr/settings.yaml`:

```yaml
selection_actions:
  enabled: true
  speech_engine: kokoro_ane   # or: system
  tidy_hotkey: { key_code: 40, modifiers: [option] }
  speak_hotkey: { key_code: 38, modifiers: [option] }
  instruct_hotkey: { key_code: 37, modifiers: [option, shift] }
```

Partial blocks are fine; omitted keys keep their defaults. Relaunch after editing.
Requirements: Accessibility, which uttr already needs for paste. Tidy and Instruct
also need Apple Intelligence (macOS 26+). The first launch downloads Kokoro and
compiles it for the Neural Engine. The load time is logged separately, because
warm-up is a separate concern from per-request latency.

Every stage logs its latency to `~/Library/Logs/uttr Debug/transcriptions.log`:

```text
[SelectionReader] Read 412 characters via accessibility in 9 ms
[SelectionActions] Transformed 412 → 398 characters in 740 ms
[SpeechPlayer] First audio after 180 ms
[SpeechPlayer] Synthesized 21.4 s of audio in 2.10 s (10.2x real time, 5 chunks)
```

These figures show the format only; they are not measurements.

## The frontier on an M2 Air with 16 GB

The M2 has a 16-core Neural Engine (about 15.8 TOPS) and 100 GB/s of unified memory
bandwidth. ASR, the LLM, and TTS all share that memory. LLM decoding is limited by
memory bandwidth, so a 4-bit 4B model (about 2.5 GB) cannot exceed about 40 tok/s
on any compute unit. Real decoding is slower.

### Language model

| Route | Hardware | Fit for uttr |
|-------|----------|--------------|
| **Apple Foundation Models** (system on-device model) | Managed by the OS. Apple does not document which compute unit it uses. | **Used here.** No download and no memory in uttr's process. PR #15 measured an 897 ms median for short cleanups on a 16 GB Mac. macOS 27 ships a rebuilt model. |
| **macOS 27 `LanguageModel` protocol** with `MLXLanguageModel` / `CoreAILanguageModel` | MLX runs on the GPU. Core AI is the route Apple says can "take advantage of the ANE". | **The swap point.** The same `LanguageModelSession` code can run an open-weight model by passing `model:`, so models can be compared without new plumbing. Needs the macOS 27 SDK. |
| **MLX / mlx-swift-lm** in-process | GPU (Metal) | Fastest practical route for open weights on a Mac. Candidates for 16 GB: Qwen3.5 2B/4B (9B fits but is slow to decode), Gemma 4 E2B/E4B, and LFM2.5 1.2B. |
| **ANE LLM runtimes** (ANEMLL, CoreML-LLM, Core AI) | Neural Engine | Lower power, but reports put 4B decode at about 9–12 tok/s, roughly half the GPU's speed. Context is often capped at 512–4096 tokens. Not the practical-speed winner for LLMs today. |
| **Ollama / llama.cpp** | GPU (Metal) | What the Python sidecar used (Llama 3.2 3B). Needs an external daemon, which uttr moved away from. |

For selection-sized edits (100–500 tokens in and out), decode time dominates. At
about 30 tok/s, a 4B model needs 5–15 s for a long paragraph, so models of 2B or
smaller are the realistic range for an action that feels instant. Apple's model is
the baseline to beat.

### Text to speech

| Option | Hardware | Notes |
|--------|----------|-------|
| **FluidAudio Kokoro ANE** (`KokoroAneManager`) | 4 of 7 Core ML stages on the ANE, 3 on the GPU | **Used here.** Already a dependency, Apache-2.0. One-shot synthesis, so text is split into sentences and pipelined: sentence one plays while sentence two is synthesized. 82M parameters. The docs report 3–11× real time. Pinned 0.14.3 has one voice (`af_heart`). |
| FluidAudio PocketTTS (`PocketTtsManager`) | **CPU + GPU** in 0.14.3; it avoids the ANE on purpose because fp16 caused audible artifacts | Streams 80 ms frames (about 80 ms to first audio per the docs) and supports voice cloning. Weights are CC-BY-4.0. Worth an A/B on latency. |
| Newer FluidAudio (0.17.x) | ANE / CPU | Kokoro v3 (multiple voices, multilingual), Paradee-8M (about 100× real time on CPU), PocketTTS small models (main only). Upgrading needs a check of the ASR API too. |
| `AVSpeechSynthesizer` (`speech_engine: system`) | OS | No download. Uses Premium or Personal Voice if installed. The fallback here. |
| Chatterbox, Qwen3-TTS 0.6B, Fish Audio S2 Pro (about 5B, non-commercial) | GPU via MLX-Audio | Higher quality ceiling, with much higher latency and memory. Out of scope for an instant action. |

## Reading the selection

Selecting text does not copy it. `SelectionReader` first asks Accessibility for the
focused element's `kAXSelectedTextAttribute`. That works in native Cocoa text views
and leaves the clipboard untouched. Browsers and Electron apps often don't expose the
selection, so the fallback sends Cmd+C and waits up to 350 ms for the pasteboard
change count to move. It then restores every pasteboard item. An unchanged count
means nothing was selected. The log records which path ran and how long it took.

## How this fits uttr

`AGENTS.md` says document-context access and new interaction surfaces need an
explicit product decision. This experiment touches both:

- **Context access is per press and user-initiated.** Each request uses a fresh model
  session and includes nothing from the clipboard or earlier requests. Rewrites go
  into history like transcriptions do. The copy fallback replaces the clipboard for
  up to 350 ms.
- **Selected text is untrusted.** The prompt treats it all as text to edit, and
  nothing is executed. A crafted selection can still steer the rewrite, and the
  output is pasted.
- **Overlap with macOS.** Writing Tools already rewrites selections, and Spoken Content
  has a built-in "Speak selection" shortcut (⌥Esc). Tidy and Speak are faster to
  invoke (one key, no UI, a local voice on the ANE), but they are not new
  capabilities.
- **Instruct is the uttr-shaped one.** It composes dictation, uttr's core primitive,
  with selection and transformation. A spoken edit in place has no direct macOS
  equivalent, so this action is the one to judge the direction by.

## Composition

Each action is `source → transform? → sink`:

| | Source | Transform | Sink |
|-|--------|-----------|------|
| Dictation today | microphone → Parakeet | none | paste |
| PR #15 cleanup | microphone → Parakeet | cleanup prompt | paste |
| Tidy | selection | tidy prompt | paste |
| Speak | selection | none | speech |
| Instruct | selection + microphone → Parakeet | dictated instruction | paste |
| Possible: "read me the gist" | selection | summarize prompt | speech |

`TextTransforming` is the shared text step, so PR #15's cleanup and these actions
could use one backend behind the macOS 27 `LanguageModel` protocol. A generic
pipeline type should wait until the transcription session owner (PRs #12/#14)
lands. Today AppDelegate owns recording, so Instruct is split across the record and
transcribe callbacks.

## Next measurements

1. Practical latency on the M2, using the log lines above: selection read (AX vs
   copy), transform time by selection length, Kokoro time to first audio and real-time
   factor.
2. Kokoro ANE vs `KokoroAneComputeUnits.cpuAndGpu` vs PocketTTS, to confirm that the
   ANE is actually the faster path for TTS on an M2.
3. On macOS 27, Apple's model vs a 1–2B MLX model behind the same session, for
   Instruct quality and latency.
4. Memory with Parakeet, Kokoro, and an MLX model loaded together.
5. Which apps answer through Accessibility and which need the copy fallback.

Sources: [FluidAudio](https://github.com/FluidInference/FluidAudio) (source at
0.14.3 and the repo docs for PocketTTS/KokoroAne),
[WWDC26: What's new in Foundation Models](https://developer.apple.com/videos/play/wwdc2026/241/),
[WWDC26: Bring an LLM provider to Foundation Models](https://developer.apple.com/videos/play/wwdc2026/339/),
[WWDC26 macOS guide (Core AI)](https://developer.apple.com/wwdc26/guides/macos/),
[Apple Neural Engine for LLM inference](https://insiderllm.com/guides/apple-neural-engine-llm-inference/),
[llms-on-apple-neural-engine benchmarks](https://github.com/cadamcat/llms-on-apple-neural-engine),
[Best local TTS models 2026](https://www.yaps.ai/blog/best-local-tts-models).
Model-size and speed figures from blog roundups are indicative, not M2 measurements.
