#!/usr/bin/env bash
# bench/run.sh  —  generate test audio clips and run the benchmark
#
# Usage:
#   ./bench/run.sh                    # table output, Parakeet v3
#   ./bench/run.sh --v2               # use Parakeet v2
#   ./bench/run.sh --markdown         # GitHub-flavoured markdown (paste into PR)
#   ./bench/run.sh --cold             # delete cached models first (measures cold load)
#   ./bench/run.sh path/to/clip.aiff  # benchmark a specific file instead
#
# Requires: Xcode CLI tools, uv (for macOS say; always present)
# Models must be downloaded at least once before running (cold flag will do it).

set -euo pipefail

BENCH_DIR="$(cd "$(dirname "$0")" && pwd)"
AUDIO_DIR="$BENCH_DIR/audio"
BENCH_ARGS=()
CUSTOM_FILES=()
COLD=false

for arg in "$@"; do
    case "$arg" in
        --cold)    COLD=true ;;
        --v2|--v3|--markdown) BENCH_ARGS+=("$arg") ;;
        *)         CUSTOM_FILES+=("$arg") ;;
    esac
done

# ── Generate test clips ────────────────────────────────────────────────────────

mkdir -p "$AUDIO_DIR"

generate() {
    local name="$1" rate="$2" text="$3"
    local path="$AUDIO_DIR/$name.aiff"
    if [ ! -f "$path" ]; then
        echo "  generating $name.aiff…"
        say -r "$rate" -o "$path" "$text"
    fi
}

SHORT_TEXT="Pack my box with five dozen liquor jugs. \
The quick brown fox jumps over the lazy dog. \
How vexingly quick daft zebras jump."

# ~90 words  ≈ 30 s at 180 wpm
MEDIUM_TEXT="Automatic speech recognition has improved dramatically in recent years, \
driven by deep learning and large-scale training data. \
Modern systems can transcribe natural conversational speech with high accuracy, \
even in the presence of background noise and multiple speakers. \
Apple Silicon's Neural Engine provides dedicated hardware acceleration \
for on-device machine learning workloads, enabling real-time transcription \
without sending audio to external servers. \
This gives users both low latency and strong privacy guarantees, \
which are especially important for professional and sensitive workflows."

# ~370 words  ≈ 2 min at 180 wpm
LONG_TEXT="The history of automatic speech recognition spans more than seven decades. \
Early systems in the nineteen fifties could recognise only isolated digits spoken by a single speaker. \
By the nineteen eighties, hidden Markov models had become the dominant approach, \
enabling continuous speech recognition for the first time. \
The nineteen nineties saw the rise of commercial products, \
though accuracy remained limited and speaker adaptation was often required. \
The deep learning revolution of the twenty tens transformed the field. \
Recurrent neural networks, then convolutional architectures, and finally transformer-based models \
pushed word error rates to new lows on standard benchmarks. \
Whisper, released by OpenAI in twenty twenty two, demonstrated that a single model \
trained on diverse multilingual data could generalise robustly across accents, \
domains, and noise conditions. \
Meanwhile, Apple has invested heavily in on-device inference through its Neural Engine, \
a dedicated matrix-multiply accelerator present in every Apple Silicon chip since the A11 Bionic. \
The Neural Engine can execute trillions of operations per second while consuming a fraction \
of the power required by GPU-based inference. \
Parakeet, developed by NVIDIA and adapted for CoreML by FluidInference, \
takes advantage of this hardware to deliver transcription that runs many times faster than real time \
on MacBook Air and MacBook Pro. \
For a menu bar dictation app, this matters enormously. \
A model that finishes transcribing a thirty-second recording in under two seconds \
feels instantaneous to the user, while one that takes ten seconds creates noticeable friction. \
Beyond raw speed, on-device processing means audio never leaves the machine, \
which is critical for users who dictate passwords, medical notes, legal documents, or personal messages. \
The combination of accuracy, speed, and privacy makes neural-engine-accelerated speech recognition \
one of the most compelling demonstrations of Apple Silicon's capabilities \
for real-world productivity software."

if [ ${#CUSTOM_FILES[@]} -eq 0 ]; then
    echo "── Generating test clips ─────────────────────────────────────────────────"
    generate "short"  180 "$SHORT_TEXT"
    generate "medium" 180 "$MEDIUM_TEXT"
    generate "long"   180 "$LONG_TEXT"
    echo ""
    CLIP_ARGS=("$AUDIO_DIR/short.aiff" "$AUDIO_DIR/medium.aiff" "$AUDIO_DIR/long.aiff")
else
    CLIP_ARGS=("${CUSTOM_FILES[@]}")
fi

# ── Cold start: wipe cached models ────────────────────────────────────────────

if [ "$COLD" = true ]; then
    VERSION="v3"
    for arg in "${BENCH_ARGS[@]}"; do
        [[ "$arg" == "--v2" ]] && VERSION="v2"
    done

    CACHE_DIR="$HOME/Library/Caches/FluidAudio"
    if [ -d "$CACHE_DIR" ]; then
        echo "── Cold start: removing $CACHE_DIR ──────────────────────────────────────"
        rm -rf "$CACHE_DIR"
        echo "  Models deleted. They will be re-downloaded on first run."
        echo ""
    else
        echo "  (no cache found at $CACHE_DIR — already cold)"
        echo ""
    fi
fi

# ── Build ──────────────────────────────────────────────────────────────────────

echo "── Building benchmark ────────────────────────────────────────────────────"
cd "$BENCH_DIR"
swift build -c release 2>&1 | grep -v "^Build complete\|^warning:"
echo ""

# ── Run ───────────────────────────────────────────────────────────────────────

echo "── Results ───────────────────────────────────────────────────────────────"
"$BENCH_DIR/.build/release/bench" "${BENCH_ARGS[@]}" "${CLIP_ARGS[@]}"
