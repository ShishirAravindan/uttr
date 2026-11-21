# Read Aloud

Select text in any app and press `⌥R`. uttr copies the selection, restores your
clipboard, and reads it with the voice chosen in Settings → Read Aloud. Press
`⌥R` again, or Stop in the menu-bar popover, to stop. History keeps what was read.

There are three kinds of voice:

| Voice | Runs on | Download | Character |
|-------|---------|----------|-----------|
| System voice | macOS speech synthesis | none | Always available; flat |
| Kokoro (default) | FluidAudio Core ML, Neural Engine/CPU | ~320 MB, on the first `⌥R` | Natural, steady |
| Expressive (mlx-audio) | Speech-LLMs on the Apple Silicon GPU, in a local Python worker | 0.9–9 GB per model, when selected | Infers tone, pacing, and emotion from the words and punctuation |

Speech-LLMs generate audio tokens with a language-model backbone, so they read
dialogue, questions, and asides differently without any markup. Everything runs
locally; the network is only used to install mlx-audio and download models.

## Expressive models

| Setting name | Hugging Face repository | Approx. size | Controls |
|--------------|------------------------|--------------|----------|
| Chatterbox Turbo | `mlx-community/chatterbox-turbo-fp16` | 0.9 GB | Variation |
| Chatterbox | `mlx-community/chatterbox-fp16` | 1.6 GB | Exaggeration, pace guidance (CFG weight), variation |
| Qwen3-TTS 1.7B VoiceDesign | `mlx-community/Qwen3-TTS-12Hz-1.7B-VoiceDesign-bf16` | 4.3 GB | Voice description (natural language), variation |
| Qwen3-TTS 0.6B CustomVoice | `mlx-community/Qwen3-TTS-12Hz-0.6B-CustomVoice-bf16` | 1.8 GB | Speaker (Ryan, Aiden, Vivian, Serena, Uncle Fu, Dylan, Eric), style direction, variation |
| Orpheus 3B (4-bit) | `mlx-community/orpheus-3b-0.1-ft-4bit` | 2.1 GB | Speaker (tara, leah, jess, leo, dan, mia, zac, zoe), variation |
| Sesame CSM 1B | `mlx-community/csm-1b` | 3.0 GB | Variation |
| MisoTTS (8-bit) | `mlx-community/MisoLabs-MisoTTS-8bit` | 9.0 GB | Variation |

Sizes are estimates shown before download; Settings shows the real total while
downloading. MisoTTS's published MLX weights are an 8B model, so despite its
conversational focus it is the largest download here. Presets live in
`MLXSpeechModel.presets` (`Swift/Speech/SpeechModels.swift`).

Speed applies to every voice, including Kokoro and the system voice: uttr
time-stretches playback without changing pitch, rather than relying on each
model's own speed support.

## Using an expressive voice

1. Settings → Read Aloud → Voice, and pick a model under **Expressive**.
2. If the mlx-audio runtime isn't installed, uttr installs it first, then
   downloads the model. The Model row shows progress; the download can be
   cancelled and resumes from what was already fetched.
3. After downloading, uttr loads the model once to fetch its codec and tokenizer
   files, then the voice is used for the next read.

Until the selected model is ready, Kokoro (or the system voice, while Kokoro
loads) keeps reading, and the popover says why. Switching voices mid-read takes
effect after the current read. Voice, style, and slider changes apply from the
next chunk, without restarting the read.

The runtime is installed into `~/Library/Application Support/uttr/mlx-audio/venv`:

- with [uv](https://docs.astral.sh/uv/) if it's at `~/.local/bin`, `~/.cargo/bin`,
  `/opt/homebrew/bin`, or `/usr/local/bin` (uv also fetches Python 3.12), or
- with a Python 3.11+ from Homebrew, python.org, or `/usr/local/bin`.

Apple's `/usr/bin/python3` is too old for mlx-audio. To use an existing Python
that already has `mlx-audio` installed, set `read_aloud.python_path` in
[Configuration](configuration.md#read-aloud).

## Managing models

Models are stored in the standard Hugging Face cache, `~/.cache/huggingface/hub`
(or `$HF_HUB_CACHE`, `$HF_HOME/hub` when uttr is started with those set), so they
are shared with other Hugging Face tools. Settings → Read Aloud → Downloaded
models → folder button opens it in Finder. Each model is a
`models--mlx-community--…` folder; move one to the Trash to delete it. uttr checks
again when Settings opens, or with the refresh button, and falls back to Kokoro if
the selected model is gone. Codec repositories fetched on first load (for example
SNAC for Orpheus or Mimi for CSM) appear as their own folders.

## Architecture

```
⌥R / popover ─▶ ReadAloud ──▶ SpeechEngine ──┬─ SystemSpeechEngine (AVSpeechSynthesizer)
   selection,      state,        protocol    ├─ KokoroSpeechEngine ─┐
   history         pause/skip                └─ MLXSpeechEngine ────┤
                                                                     ▼
                                         SpeechPipeline (chunks, prefetch, order)
                                                  │ synthesize          │ play
                                                  ▼                     ▼
                              Kokoro / MLXAudioRuntime          SpeechAudioPlayer
                                         │ HTTP on 127.0.0.1     (AVAudioEngine +
                                         ▼                        time-pitch speed)
                              mlx_audio_worker.py ─▶ mlx-audio ─▶ Metal GPU
```

| File | Responsibility |
|------|----------------|
| `Speech/ReadAloud.swift` | Selection → history → engine; `ReadAloudState` for the icon and popover; pause, skip, stop; deferred voice switches |
| `Speech/SpeechEngine.swift` | The `SpeechEngine` protocol and `SpeechProgress` |
| `Speech/SystemSpeechEngine.swift` | macOS system voice |
| `Speech/SpeechPipeline.swift` | Shared chunk scheduler for Kokoro and mlx-audio voices |
| `Speech/SpeechAudioPlayer.swift` | One AVAudioEngine for clips at any sample rate; speed via `AVAudioUnitTimePitch` |
| `Speech/SpeechChunks.swift` | Sentence splitting (Kokoro) and 1–3 sentence grouping (speech-LLMs) |
| `Speech/KokoroSpeechEngine.swift` | Kokoro synthesis through the pipeline |
| `Speech/MLXSpeechEngine.swift` | A preset's requests through the pipeline |
| `Speech/MLXAudioRuntime.swift` | Worker process lifetime, HTTP client, idle shutdown |
| `Speech/MLXAudioInstaller.swift` | Runtime install, model download, cache paths |
| `Speech/SpeechModels.swift` | Voices, presets, per-model options, request body |
| `Speech/WAVDecoder.swift` | The worker's WAV responses to mono samples |
| `Speech/ReadAloudVoices.swift` | Picks the engine for the selected voice; install and model state for Settings |
| `Resources/mlx_audio_worker.py` | The Python bridge, bundled in the app |
| `ReadAloudSettingsView.swift`, `MenuBarPopoverView.swift` | Settings section; popover controls |

### Chunking and streaming

Speech-LLMs are autoregressive and read best with one to three sentences of
context. `SpeechChunks.groups` splits with `NLTokenizer`, keeps punctuation and
quotes with their words, makes the first chunk a single sentence for fast first
audio, then joins up to three sentences within about 240 characters. A sentence
over 400 characters is split after clause punctuation (`, ; : —`) before it is
split between words.

`SpeechPipeline` synthesizes one chunk at a time and stays at most two chunks
ahead of the one playing, so prefetching overlaps playback without holding a long
selection in memory or keeping the GPU busy after a stop. Two clips are queued
at the player, so sentences play back to back. Results and playback callbacks
carry a token, so anything from a stopped or skipped chunk is ignored.

- **Stop** (`⌥R`, popover, or a recording starting) is synchronous: queued audio
  is dropped, the synthesis task is cancelled, and the worker is told to abandon
  that request by ID. The worker checks between generated segments.
- **Skip** drops the current clip, starts the next one if it's ready, and cancels
  synthesis of any chunk skipped past.
- **Pause** pauses the player; synthesis keeps filling the two-chunk window.
- A chunk that fails is skipped. Two failures in a row, or a runtime error such as
  a missing install or a crashed worker, end the read and say why.

### Worker lifecycle

`MLXAudioRuntime` starts the worker on the first sentence, never at launch:
`venv/bin/python -u mlx_audio_worker.py serve --port 0 --parent-pid <uttr>`. The
worker binds a free localhost port and prints it, so there is no port race. It
loads the requested model on first use and keeps one model in memory; loading
another frees the first.

The worker stays warm between sentences and reads. After the idle timeout
(default 5 minutes, set under Unload after) with no requests, uttr terminates it,
returning the model's unified memory; the Worker row's eject button does it at
once. On quit, `applicationWillTerminate` signals the worker and any download
synchronously. The worker also polls its parent and exits if uttr disappears, so
a crash doesn't leave a model resident. A worker that exits unexpectedly fails the
current read and is relaunched by the next one; one that doesn't print its port
within 90 seconds is stopped.

The popover and Settings show the runtime state: not installed, installing,
starting, loading the model, warm, or the error.

### Worker protocol

The worker is a small standard-library HTTP server around mlx-audio's
`load_model` and each model's `generate`. uttr uses it instead of
`mlx_audio.server` because that server's speech request has no fields for
Chatterbox's exaggeration and CFG weight, no way to cancel a request, and no
parent-death exit.

| Endpoint | Body | Result |
|----------|------|--------|
| `GET /health` | | `{"status": "ok", "model": …}` |
| `POST /v1/models` | `{"model"}` | Loads the model |
| `POST /v1/audio/speech` | `model`, `input`, `voice`, `instruct`, `mode`, `lang_code`, `temperature`, `exaggeration`, `cfg_weight`, `request_id` | 16-bit mono WAV, `X-Sample-Rate` |
| `POST /v1/cancel` | `{"request_id"}` | Stops that request; it answers 499 |

Options a model's `generate` doesn't accept are dropped by signature, so one
request shape serves every family. `mode` selects Qwen3's
`generate_voice_design` or `generate_custom_voice` when the model has them.
`download REPO` prints JSON progress lines, and `check` confirms mlx-audio
imports.

## Storage

| Data | Location |
|------|----------|
| Runtime | `~/Library/Application Support/uttr/mlx-audio/venv` |
| Worker and installer log | `~/Library/Application Support/uttr/mlx-audio/worker.log` |
| Expressive models | Hugging Face cache, `~/.cache/huggingface/hub/models--…` |
| Kokoro | FluidAudio's cache under `~/.cache/fluidaudio/Models/` |
| Settings | `read_aloud` in `settings.yaml` ([Configuration](configuration.md#read-aloud)) |

## Troubleshooting

- **"Install uv … or Python 3.11 or later"**: install one (`brew install uv`), then
  Install in Settings → Read Aloud → mlx-audio runtime.
- **A model fails on every chunk**: see `worker.log` (folder button on the runtime
  row). Reinstall updates mlx-audio, which may be needed for newer model families.
- **First read after a while is slow**: the worker unloaded after the idle
  timeout; the popover shows "Loading … into memory". Raise Unload after if you
  read often.
- **Memory**: a loaded model holds roughly its download size in unified memory
  until it unloads.

## Validation

The standalone checks cover the parts that don't need a microphone, GPU, or
model; see [Development](development.md#standalone-checks):

- `Tests/SpeechChecks.swift`: chunking and grouping; voice switching; read-aloud
  state, pause, skip, and failures.
- `Tests/SpeechPipelineChecks.swift`: order, the prefetch bound, stop cancelling
  synthesis promptly, skip, pause, failures, stale callbacks.
- `Tests/MLXAudioChecks.swift`: lazy start, one worker for concurrent requests,
  warm reuse, idle shutdown (never mid-request), relaunch after an exit, shutdown
  on quit, cancellation reaching the worker, startup timeout, model switching,
  WAV decoding, presets, the cache check, and a read through `MLXSpeechEngine`.
- `Tests/mlx_audio_worker_checks.py`: the worker against fake mlx-audio and
  Hugging Face packages: serving, option filtering, cancellation, model switching,
  exiting with its parent, and download progress.

Real synthesis, audio output, model downloads, and how each model sounds need a
manual check on an Apple Silicon Mac.
