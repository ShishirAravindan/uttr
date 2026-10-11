# Working on uttr

## Current app

uttr is a Swift macOS menu-bar app. AppDelegate in `Swift/uttr.swift` coordinates
native-format WAV capture, local Parakeet inference through FluidAudio, history,
and paste-at-cursor. Use the current source and [architecture](docs/architecture.md)
when older branches or notes disagree. Unmerged code is not shipped behavior.

Keep the registered Carbon hotkey, local inference, and existing menu-bar surface
in view when changing the product. Continuous listening, document-context access,
and additional interaction surfaces need an explicit product decision.

## Implementation and validation

- Keep device handling in AudioRecorder/AudioDeviceManager, model integration in
  the provider, and platform delivery in PasteManager. AppDelegate currently owns
  orchestration; do not assume a separate session owner or serialized workflow.
- For recording, transcription, delivery, or provider-lifecycle changes, read
  [uttr-dictation-work](.agents/skills/uttr-dictation-work/SKILL.md).
- Use existing DesignTokens and native macOS controls for UI work. Preserve the
  Release identity when updating the separate Debug asset set or permission flow.
- New Swift files need Xcode project references and target membership. Preserve
  the existing Info.plist arrangement: generated keys plus `uttr-Info.plist`.
- Validate the changed behavior. Build verification should use Xcode or a temporary
  derived-data directory; `build.sh` in Release replaces `/Applications/uttr.app`.
  Builds do not establish live microphone, model inference, or paste behavior.
- `Tests/LoggerChecks.swift` is the current standalone check. There is no lifecycle
  XCTest target on main. Keep tests free of the user's history, clipboard, audio,
  and permission grants unless a live check is explicitly intended.

## Docs and diagrams

Document the implementation that has landed. Keep settings, storage paths, app
requirements, and release instructions consistent with source and workflows.
Store rendered Excalidraw PNGs in `docs/assets/diagrams/` and reference them directly
from Markdown. `.excalidraw` scenes are local, ignored working files. Check links,
scene references, and rendered layout ad hoc; do not introduce permanent diagram
validation jobs unless requested. See [Development](docs/development.md).

## Git and review

Check status and current main before branching; preserve unrelated local changes.
Use the origin repository explicitly when `gh` sees both origin and upstream.
Check author/committer identity against the user's configured profile and recent
commits before committing; do not change it without authorization.

Use conventional commits: `type(optional-scope): imperative description`. One
commit does one thing. Tests get their own commits within the same PR. Changes to
agent instructions need a body explaining why the guidance is useful. Do not add
agent attribution trailers. PRs should describe the concrete behavior and relevant
validation, with any remaining manual checks.

`backlog.md` is ignored local planning material; keep it out of commits and PRs.
Keep shared conventions here and focused reusable workflows under `.agents/skills`.
Avoid parallel editor-specific rules or placeholder skills.
