# Architecture

## Overview

### Transcribe Flow (STT only)
1. Transcribe hotkey pressed (⌥L default) → Swift records audio
2. Swift saves audio to file → calls Python server `/transcribe` API
3. Python runs Whisper/Parakeet STT → returns raw transcription
4. Swift receives text → pastes at cursor → logs

### Transform Flow
1. Transform hotkey pressed (⌥S default) → Swift reads clipboard
2. Swift calls Python server `/transform` API with text + mode
3. Python runs LLM with mode-specific prompt → returns transformed text
4. Swift receives text → pastes at cursor

## Components Map

### Swift
- `Swift/uttr.swift`: App lifecycle & coordination
- `Swift/AudioRecorder.swift`: AVAudioEngine wrapper (16kHz mono)
- `Swift/HotkeyManager.swift`: Global hotkey registration (transcribe + transform)
- `Swift/PasteManager.swift`: Clipboard & paste
- `Swift/TranscriptionServer.swift`: Launches embedded server with `uv`
- `Swift/TranscriptionServerClient.swift`: HTTP client (`/transcribe`, `/transform`)
- `Swift/SettingsManager.swift`: YAML-backed settings (App Support)
- `Swift/MenuBarIconManager.swift`: Status bar icon states & animations

### Python (`stt-server-py/`)
- `transcription_server.py`: aiohttp server (`/transcribe`, `/transform`, `/providers`, `/reload_model`, `/health`)
- `whisper_STTProvider.py`: Whisper integration
- `parakeet_STTProvider.py`: Parakeet MLX integration (Apple Silicon optimized)
- `llm_processor.py`: LLM postprocessing (Ollama)
- `config.py`: YAML loader
- `settings.yaml`: Default config example
- `pyproject.toml`: Dependencies (managed by `uv`)

## Server Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/transcribe` | POST | Transcribe audio file to text |
| `/transform` | POST | Transform text using LLM with specified mode |
| `/providers` | GET | List available STT providers |
| `/switch_provider` | POST | Switch active STT provider |
| `/reload_model` | POST | Reload Whisper model with new config |
| `/health` | GET | Health check |

## Server Modes
- **Embedded (default)**: Swift launches `uv run python transcription_server.py` with the app settings file.
- **Manual**: Run server from terminal for development; point app to host/port.

## Transform Modes
Transform modes are configured in `settings.yaml` under the `transform.modes` key. Each mode has a custom LLM prompt template.

Default mode: `bullets` - Converts text into clear, concise bullet points.
