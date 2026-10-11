<img src="docs/assets/logo.png" alt="uttr" width="96">

# uttr

A macOS menu bar app for fast, local speech-to-text transcription. Press a hotkey, speak, and the transcribed text is automatically pasted at your cursor. No cloud transcription, Python, or separate runtime to install.

Powered by Parakeet v3 (multilingual) or v2 (English) running locally via [FluidAudio](https://github.com/FluidInference/FluidAudio).

## Installation

```bash
brew tap ShishirAravindan/tap
brew install --cask uttr
```

That's it. No Python, no `uv`, no setup.

## Quick Start

1. Launch **uttr** — the icon appears in your menu bar
2. Grant permissions when prompted: **Microphone** and **Accessibility**
3. Press the hotkey (default: `⌥L`) to start recording
4. Speak, then press the hotkey again to stop
5. Transcribed text is pasted at your cursor

On first launch, uttr downloads the Parakeet model (~600 MB) in the background. The menu bar shows a loading indicator until it's ready.

## Configuration

Settings are stored at `~/Library/Application Support/uttr/settings.yaml`.

Configure via menu bar → Settings, or edit the YAML directly.

See [Configuration Guide](docs/configuration.md) for all options.

## Documentation

- [Getting Started](docs/getting-started.md) — Detailed setup and first-run guide
- [Configuration](docs/configuration.md) — All settings explained
- [Architecture](docs/architecture.md) — How it works (for contributors)
- [Development](docs/development.md) — Building from source
- [Troubleshooting](docs/troubleshooting.md) — Common issues and fixes
- [Releasing](docs/releasing.md) — GitHub Actions and Homebrew tap updates

## Requirements

- macOS 15.5 or later
- Apple Silicon (M1 or later) — required for the Neural Engine

## Contributing

Contributions are welcome. See [CONTRIBUTING.md](docs/CONTRIBUTING.md) for guidelines.

## License

[MIT](LICENSE)
