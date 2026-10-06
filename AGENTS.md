# Working on uttr

## Product and architecture

uttr is a macOS menu-bar app written in Swift. AudioRecorder writes native-rate
WAV audio; FluidAudio runs Parakeet in-process; PasteManager inserts one completed
transcript at the cursor. There is no Python sidecar or LLM cleanup stage today.
Use the current source and [architecture guide](docs/architecture.md) when older
notes disagree with them.

Keep speech capture quick to invoke and quick to leave. The keyboard remains the
primary input. Preserve local inference, the existing menu-bar surface, and the
registered Carbon hotkey's limited scope. Features that read document context,
monitor unrelated keystrokes, or listen continuously need their own product
decision; they are not incidental extensions of dictation.

The arguments on the `design-notes` branch are useful design references, not a
specification to implement wholesale. Read `docs/operational-notes.md` and the
relevant essay with `git show origin/design-notes:<path>` when they are not in the
checkout. In particular, `speech-and-typing.md` motivates cleanup and `ambient.md`
explains the costs of automatic stopping, clipboard borrowing, and extra surfaces.

## Scope and consistency

- One component owns each workflow and its state. AppDelegate owns app lifecycle,
  windows, menu-bar wiring, and system integration; TranscriptionSession owns the
  recording-to-insertion workflow. Views and icons reflect session state. A new
  recording waits until the current transcription and insertion finish.
- Keep state transitions on the main actor. Own asynchronous tasks explicitly;
  prevent stale completions from changing newer state. Stop using a provider before
  tearing it down. Preserve behavior during extraction and call out deliberate
  changes, including whether another utterance can start while one is processing.
- Keep audio-device handling in AudioRecorder/AudioDeviceManager. Do not fold the
  known Bluetooth capture-only dropout issue into an unrelated refactor.
- Use existing DesignTokens and macOS controls for UI changes. App icons are static
  asset sets. Preserve the Release identity when changing Debug behavior.
- Logging, storage migration, clipboard correctness, and post-utterance cleanup
  are separate work items. Moving code does not implicitly fix them.
- `backlog.md` is local planning material. Keep it ignored and out of README,
  commits, and PR descriptions. Update completion status only from actual results.

## Task guidance

For recording, transcription, delivery, or session-lifecycle work, read
[uttr-session-work](.agents/skills/uttr-session-work/SKILL.md). It covers the
workflow boundaries and validation strategy for these changes. For UI-only work,
use [DesignTokens](Swift/Design/DesignTokens.swift) and the existing views.

Adding Swift files requires Xcode references and target membership. Preserve the
existing project settings and Info.plist arrangement. The shared configuration
lives in this file and `.agents/skills`; avoid parallel editor-specific rule sets.

## Git and review

Check status and the latest main before branching. Keep unrelated local changes.
Use meaningful branches such as `refactor/transcription-session`. Reuse existing
candidate work only after reviewing it; local branches are not evidence of a fix
being shipped.

Before committing, verify `git var GIT_AUTHOR_IDENT` and
`git var GIT_COMMITTER_IDENT` against recent commits and the user's chosen profile.
Do not change identity or add an agent attribution trailer.

Use conventional commits: `type(optional-scope): imperative description`. One
commit does one thing. Tests have their own commits within the same PR. Changes
to agent instructions use a body explaining why the guidance is needed.

PRs should state the concrete problem, resulting behavior, and relevant validation
in a few sentences or short bullets. Disclose intentional behavior changes and
limitations. Avoid conversational history and boilerplate. Use the origin repo
explicitly with `gh` when an upstream remote is also configured.

## Reusable skills

Keep shared repository conventions here. When a task develops a repeated,
non-obvious workflow, put a focused skill in `.agents/skills/<name>/SKILL.md` with
`name` and `description` frontmatter. Read the skill-creator guidance when creating
one, validate it, and link to existing sources instead of copying conventions.
Add scripts or supporting files only when repetition or reliability justifies
them. Do not create placeholder skills for work that has not demonstrated a need.
