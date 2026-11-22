# Read Aloud

Select text in any app and press `⌥R`. uttr copies the selection, restores your
clipboard, and reads it with the voice chosen in Settings → Text to Speech. Press
`⌥R` again, or Stop in the menu-bar popover, to stop. History keeps what was read.

There are three kinds of voice, all running inside uttr:

| Voice | Runs on | Download | Character |
|-------|---------|----------|-----------|
| System voice | macOS speech synthesis | none | Always available; flat |
| Kokoro (default) | FluidAudio Core ML, Neural Engine/CPU | ~320 MB, on the first `⌥R` | Natural, steady |
| Expressive | Speech-LLMs on the Apple Silicon GPU through [mlx-audio-swift](https://github.com/Blaizzy/mlx-audio-swift) | 0.6–4.3 GB per model, when selected | Infers tone, pacing, and emotion from the words and punctuation |

Speech-LLMs generate audio tokens with a language-model backbone, so they read
dialogue, questions, and asides differently without any markup. There is no
Python or helper process: the network is only used to download models.

## Expressive models

| Setting name | Hugging Face repository | Approx. size | Voice character | Advanced |
|--------------|------------------------|--------------|-----------------|----------|
| Chatterbox Turbo | `mlx-community/chatterbox-turbo-8bit` | 0.6 GB | — | Variation, consistent voice |
| Chatterbox | `mlx-community/Chatterbox-TTS-fp16` | 1.6 GB | Emotion, pace guidance | Variation, consistent voice |
| Qwen3-TTS 1.7B VoiceDesign | `mlx-community/Qwen3-TTS-12Hz-1.7B-VoiceDesign-bf16` | 4.3 GB | Voice description | Variation, top-p, repetition penalty, consistent voice |
| Qwen3-TTS 0.6B CustomVoice | `mlx-community/Qwen3-TTS-12Hz-0.6B-CustomVoice-bf16` | 1.8 GB | Speaker (Ryan, Aiden, Vivian, Serena, Uncle Fu, Dylan, Eric), style direction | Variation, top-p, repetition penalty, consistent voice |
| Orpheus 3B (4-bit) | `mlx-community/orpheus-3b-0.1-ft-4bit` | 2.1 GB | Speaker (tara, leah, jess, leo, dan, mia, zac, zoe) | Variation, top-p, repetition penalty, consistent voice |
| Marvis 250M | `Marvis-AI/marvis-tts-250m-v0.2-MLX-8bit` | 0.6 GB | Speaker (conversational A/B, French, German) | Variation, consistent voice |

Sizes are estimates. Codec and tokenizer repositories a model needs (for example
SNAC for Orpheus) download the first time it loads. Orpheus also understands
inline tags such as `<laugh>` and `<sigh>` in the selected text.

Sesame CSM and MisoTTS, offered when expressive voices ran in a Python worker,
have no Swift implementation and were dropped; Marvis is a small model in the
same conversational style. A settings file that still names one falls back to
Kokoro.

## Settings → Text to Speech

The pane is built in tiers, so the default experience stays short:

1. **Voice**: shortcut, voice, speed (0.75–1.5×, every voice, pitch preserved),
   and Preview, which reads a short sample with dialogue and a question.
2. **The model's card** (expressive voices only): download state with
   download/cancel, then the dials that shape how the voice sounds.
3. **Advanced** (collapsed): sampling dials, keeping the voice consistent,
   sentences per chunk, how long the model stays in memory, and resetting the
   model to its defaults.

Each preset declares its dials as data (`TTSParameter` in
`Swift/Speech/SpeechModels.swift`): an ID, label, caption, kind (slider, choice,
text, or toggle), tier, and default. Settings draws controls from that list, so
choosing defaults or hiding a dial is a change to the catalog, not to the UI.
Only values that differ from a default are saved, so improved defaults reach
anyone who hasn't changed them. Sampling dials with no default show "Default"
and leave the value to the model.

**Keep the voice consistent** (on by default) seeds the random generator the
same way for every chunk, so a designed or sampled voice doesn't drift between
sentences.

Choosing an expressive voice downloads it. Until it is ready, Kokoro (or the
system voice, while Kokoro loads) keeps reading, and the pane and popover say
why. Switching voices mid-read takes effect after the current read; dial changes
apply from the next chunk.

## Managing models

Settings → General → Storage lists downloaded expressive voices with their size
and whether one is in memory. Remove deletes a model after confirming; the folder
button reveals it in Finder. Models live in mlx-audio-swift's folder in the
Hugging Face cache, `~/.cache/huggingface/hub/mlx-audio/<org>_<name>` (or under
`$HF_HUB_CACHE` / `$HF_HOME/hub` when uttr is started with those set). Deleting a
folder in Finder works too; uttr notices when Settings opens or with the refresh
button, and falls back to Kokoro if the selected model is gone.

## Architecture

```
⌥R / popover ─▶ ReadAloud ──▶ SpeechEngine ──┬─ SystemSpeechEngine (AVSpeechSynthesizer)
   selection,      state,        protocol    ├─ KokoroSpeechEngine ─┐
   history         pause/skip                └─ MLXSpeechEngine ────┤
                                                                     ▼
                                         SpeechPipeline (chunks, prefetch, order)
                                                  │ synthesize          │ play
                                                  ▼                     ▼
                                  Kokoro / TTSModelHost          SpeechAudioPlayer
                                               │                 (AVAudioEngine +
                                               ▼                  time-pitch speed)
                                  mlx-audio-swift ─▶ MLX ─▶ Metal GPU
```

| File | Responsibility |
|------|----------------|
| `Speech/ReadAloud.swift` | Selection → history → engine; `ReadAloudState` for the icon and popover; pause, skip, stop; deferred voice switches |
| `Speech/SpeechEngine.swift`, `Speech/SystemSpeechEngine.swift` | The `SpeechEngine` protocol and `SpeechProgress`; the system voice |
| `Speech/SpeechPipeline.swift` | Shared chunk scheduler for Kokoro and expressive voices |
| `Speech/SpeechAudioPlayer.swift` | One AVAudioEngine for clips at any sample rate; speed via `AVAudioUnitTimePitch` |
| `Speech/SpeechChunks.swift` | Sentence splitting (Kokoro) and 1–3 sentence grouping (speech-LLMs) |
| `Speech/KokoroSpeechEngine.swift` | Kokoro synthesis through the pipeline |
| `Speech/MLXSpeechEngine.swift` | A preset's requests through the pipeline |
| `Speech/SpeechModels.swift` | Voices, presets, the parameter schema, and request building |
| `Speech/TTSModelHost.swift` | The loaded model's lifetime, serialized generation, idle unload; model files on disk |
| `Speech/MLXAudioBackend.swift` | The only code that calls mlx-audio-swift: loading, generation, downloads |
| `Speech/ReadAloudVoices.swift` | Picks the engine for the selected voice; download, removal, and storage state |
| `TextToSpeechSettingsView.swift`, `SettingsTabView.swift`, `MenuBarPopoverView.swift` | Settings panes; popover controls |

### Chunking and streaming

Speech-LLMs are autoregressive and read best with one to three sentences of
context. `SpeechChunks.groups` splits with `NLTokenizer`, keeps punctuation and
quotes with their words, makes the first chunk a single sentence for fast first
audio, then joins up to three sentences (Sentences per chunk) within about 240
characters. A sentence over 400 characters is split after clause punctuation
(`, ; : —`) before it is split between words.

`SpeechPipeline` synthesizes one chunk at a time and stays at most two chunks
ahead of the one playing, so prefetching overlaps playback without holding a long
selection in memory or keeping the GPU busy after a stop. Two clips are queued
at the player, so sentences play back to back. Results and playback callbacks
carry a token, so anything from a stopped or skipped chunk is ignored.

- **Stop** (`⌥R`, popover, or a recording starting) is synchronous: queued audio
  is dropped and the synthesis task is cancelled; mlx-audio-swift's models check
  for cancellation while generating.
- **Skip** drops the current clip, starts the next one if it's ready, and cancels
  synthesis of any chunk skipped past.
- **Pause** pauses the player; synthesis keeps filling the two-chunk window.
- A chunk that fails is skipped; two failures in a row end the read. A model that
  can't load ends the read at once and says why.

### Model lifetime

`TTSModelHost` holds at most one expressive model. It loads on the first sentence
(never at launch), and mlx-audio-swift downloads anything missing. Generation is
serialized: mlx-audio-swift models must not be used concurrently, so a chunk
waits its turn, and a chunk cancelled while waiting never runs. Switching to
another expressive voice drops the previous model first.

The model stays warm between sentences and reads. After the idle timeout
(default 5 minutes, Advanced → Unload after) with no requests, the host drops it
and clears MLX's buffer cache, returning its unified memory; Advanced → Memory
unloads at once. Quitting drops it and cancels downloads.

Downloading fetches the weights with progress, then loads the model once so codec
and tokenizer repositories arrive before the first read; the model then stays
warm until the idle timeout.

## Dependencies

mlx-audio-swift is pinned to a commit in the Xcode project, since it has no
tagged releases; update the pin deliberately and re-test each model family. It
brings mlx-swift and swift-huggingface, which uttr also imports directly for
`MLX` and `HuggingFace`. mlx-audio-swift needs Swift 6.3 (Xcode 26.4 or later),
and MLX's Metal shaders build only in Xcode.

## Storage

| Data | Location |
|------|----------|
| Expressive models | `~/.cache/huggingface/hub/mlx-audio/<org>_<name>` |
| Kokoro | FluidAudio's cache under `~/.cache/fluidaudio/Models/` |
| Settings | `read_aloud` in `settings.yaml` ([Configuration](configuration.md#read-aloud)) |

## Troubleshooting

- **A model fails to load**: the error shows in the pane and popover, and the
  log has details. Remove it in General → Storage and download it again.
- **First read after a while is slow**: the model unloaded after the idle
  timeout; the popover shows "Loading … into memory". Raise Unload after if you
  read often.
- **The voice changes between sentences**: turn on Keep the voice consistent, or
  lower Variation.
- **Memory**: a loaded model holds roughly its download size in unified memory
  until it unloads.

## Validation

The standalone checks cover the parts that don't need a microphone, GPU, or
model; see [Development](development.md#standalone-checks):

- `Tests/SpeechChecks.swift`: chunking and grouping; voice switching; read-aloud
  state, pause, skip, and failures.
- `Tests/SpeechPipelineChecks.swift`: order, the prefetch bound, stop cancelling
  synthesis promptly, skip, pause, failures, stale callbacks.
- `Tests/ExpressiveVoiceChecks.swift`: lazy loading, one load for concurrent
  chunks, generation never overlapping, warm reuse, idle unload (never
  mid-generation), model switching, load failures, unloading during a load,
  cancellation while waiting and while generating; the preset catalog, request
  building, saved values, the downloaded-model check, and a read through
  `MLXSpeechEngine`.

`MLXAudioBackend.swift` and real synthesis, downloads, audio output, and how
each model sounds need a build and a manual check on an Apple Silicon Mac.
