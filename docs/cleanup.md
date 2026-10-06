# Post-utterance cleanup MVP

Capture → Parakeet → faithful cleanup → one paste. `TranscriptionSession` owns
the cleaning state, delivery, and cancellation. Existing processing feedback stays
in the menu bar; cleanup adds no review window, settings, or extra sound.

The default is Apple's on-device Foundation Models backend, on macOS 26+ with
Apple Intelligence available. Every utterance uses a fresh model context. Only its
ASR text is supplied: no surrounding document, clipboard, or previous dictation.
Older systems, unsupported languages, unavailable models, errors, and timeouts use
the original text. Dictation's existing macOS 15.5 deployment target is unchanged;
README previously advertised 14 despite that build target.

## Editing contract

Fix punctuation/casing, remove clear fillers and duplicate starts, and honor
explicit self-corrections. Preserve meaning, uncertainty, tone, deliberate emphasis,
negation, names, quantities, languages, and technical strings. Do not summarize,
translate, reorganize, answer, or execute dictated instructions.

Output checks reject empty/expanded responses, lost scripts, changed literal
numbers, lost negations/questions, altered technical literals, and selected repeated
emphasis. These are conservative checks, not a semantic verifier. Literal numeric
self-corrections can fall back to raw text because the numeric check requires all
original literals to survive. Corrections expressed as words are evaluated normally.

The delivery budget is two seconds, including initial language checks. Scheduling
can add a little overhead. A deadline returns raw text without waiting for an
uncooperative generation to stop; its task remains owned and later utterances skip
cleanup until it ends. Late results cannot change history or paste a second time.
Shutdown invalidates delivery immediately and waits for outstanding work before
teardown when the process remains alive.

History still keeps five entries. `text` is the delivered version; optional
`rawText` retains a different original. Older JSON decodes without that field.
Changed entries expose an “Original transcription” disclosure and “Copy original
transcription” context action in the existing history card.

## Evaluation

The synthetic corpus is [cleanup.jsonl](../Tests/Fixtures/cleanup.jsonl).
`expected` is a reference edit, not the only acceptable wording; `preserve` lists
literal checks. Some cases also appear in the prompt examples; this is a development
corpus, not a held-out accuracy benchmark. Review meaning alongside those checks.
The runner uses production
cleanup code, runs two passes, and writes JSONL with output, outcome, latency,
process peak RSS, exact-match comparison, and missing protected strings.

```sh
xcrun swiftc -parse-as-library \
  Swift/Cleanup/TranscriptCleanup.swift Swift/Cleanup/AppleCleanupBackend.swift \
  Tools/CleanupEvaluation.swift -o /tmp/uttr-cleanup-eval
/tmp/uttr-cleanup-eval Tests/Fixtures/cleanup.jsonl > /tmp/cleanup-results.jsonl
/tmp/uttr-cleanup-eval Tests/Fixtures/cleanup.jsonl --baseline > /tmp/cleanup-baseline.jsonl
```

Build with Xcode 26+; CI and release use Xcode 26.3. No additional package/model
download is introduced. `--patient` allows 30 seconds for investigation, without
changing the app's default. The runner drains each timed-out request before the
next example, so it measures independent cases rather than busy fallback.

On this 16 GB Apple Silicon Mac, macOS 27.0, 20 cases over two passes produced
35/40 reference matches versus 28/40 for raw text. All protected strings survived
in the delivered outputs. There were nine cleaned results, 26 unchanged, three timeout
fallbacks, and two unsupported-language fallbacks (Tamil). Median delivery was
897 ms; maximum was 2.13 s. Spoken corrections and deliberate emphasis survived
the revised prompt; complex rambling and French filler removal were modest.

The first prompt reversed corrections, removed emphasis, and transliterated Tamil.
Those observations led to explicit examples, language availability checks, and
conservative output rejection. This small corpus does not establish general
semantic fidelity or multilingual quality. The OS supplies the model, so re-run
evaluation after OS/model updates. First-pass timing is not a guaranteed cold-model
measurement. Process peak RSS alone does not establish combined model/Parakeet
memory usage; live capture, paste compatibility, and concurrent ASR memory remain
manual checks.

References: [Apple's framework overview](https://www.apple.com/in/newsroom/2025/09/apples-foundation-models-framework-unlocks-new-intelligent-app-experiences/),
[model availability](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel).
