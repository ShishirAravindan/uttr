# Contributing

Contributions are welcome. This guide will help you get started.

## Getting Started

1. **Fork the repository** on GitHub
2. **Clone your fork:**
   ```bash
   git clone https://github.com/YOUR_USERNAME/uttr.git
   cd uttr
   ```
3. **Set up the development environment** — See [Development Guide](development.md)

## Making Changes

### 1. Create a Branch

```bash
git checkout -b feature/your-feature-name
# or
git checkout -b fix/your-bug-fix
```

### 2. Make Your Changes

- Keep changes focused and atomic
- Follow the code style guidelines below
- Update documentation if needed

### 3. Test Your Changes

- For app changes, build the affected configuration and test the changed behavior
  manually, including capture, transcription, and paste when those paths change.
- For logger changes, run the standalone [logger checks](development.md#logger-checks).
- For documentation changes, check relative links and image references. Inspect
  diagram exports at a readable size and verify their claims against current code.

PR builds run the Release build and logger checks. A successful build does not
establish live microphone, model inference, or paste behavior.

### 4. Commit Your Changes

```bash
# Good
git commit -m "docs: correct first-run model preparation"
git commit -m "fix: re-register hotkeys after permission changes"

# Bad
git commit -m "Fixed stuff"
```

### 5. Push and Create a Pull Request

```bash
git push origin feature/your-feature-name
```

Open a Pull Request with a clear description of what changed and why, and steps to test.
Use conventional commits and keep each commit focused on one change. Tests get
their own commits within the same PR. Changes to agent instructions should include
a commit body explaining why the guidance is needed.

## Code Style

- **One file per component** — each Swift file has a single responsibility
- **Use Logger** — all logging through the `Logger` class, not `print()`
- **Prefer async/await** — for asynchronous operations
- **Follow existing patterns** — look at similar code in the codebase

## Architecture Guidelines

uttr is a single-tier Swift app. All transcription runs in-process via FluidAudio on the Neural Engine. There is no server tier, no Python, and no network communication after the initial model download.

See [Architecture](architecture.md) for the full component map.

## What to Contribute

Good starting points: bug fixes, documentation improvements, performance optimizations. For new features, open an issue to discuss first.

## Questions?

Open an issue for bugs or feature requests, or start a discussion for questions.
