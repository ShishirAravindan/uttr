# Axes and Modes

*How this application acquired an interaction model nobody chose.*

---

## 1. The apparent taxonomy

Ask anyone who has used more than one transcription tool how such tools work, and you will get back a taxonomy with two entries.

There is **push-to-talk**: you hold a key, you speak, you release, and the text appears. And there is **dictate**: you press a key once, the app begins listening, words appear as you say them, and you press again to stop.

The two feel genuinely different to use, and the difference seems fundamental rather than incidental. One is a gesture you perform with your body. The other is a session you enter and leave. One gives you nothing until you are finished; the other narrates itself. Products advertise which one they are. Users have preferences between them.

So it looks like a taxonomy: a fact about the domain, the way "cars have automatic or manual transmissions" is a fact about cars.

It is a coincidence that has been mistaken for a category, and the mistake is expensive in a specific way. It hides the fact that you have already made design decisions you do not remember making.

## 2. What any transcription tool must do

Start further back, from the structure of the problem rather than from the products.

A tool that turns speech into text in a running computer must do at least three things.

It must know which audio to transcribe. A speech recognizer does not consume an infinite stream and emit an infinite stream; it consumes a *span*. Some boundary marks where the interesting audio starts and where it ends. Call this **delimitation**.

It must decide when the user learns what it heard. The transcript comes into existence at some moment, the user perceives it at some moment, and these need not be the same moment. There is necessarily a gap, and the size of the gap is a choice. Call it **feedback**.

It must put the text somewhere. Text is useless inside the app. It has to arrive in the document, the message box, the terminal, wherever the user was already working. Call it **delivery**.

These three are not a complete carve-up of the problem, and it is worth saying so early, because the temptation to present three tidy axes as *the* joints of the domain is exactly the kind of claim that survives on symmetry rather than argument. At least one more axis is defensible and is discussed in the companion note: whether the transcript is **transformed** before insertion, by a language model that adds punctuation, removes disfluency, or adjusts register. Retention is arguably another: what happens to the audio and the transcript afterwards. The three below are the ones that determine how the tool *feels* in use, which is why they are the ones this note is about, but a reader should hold them as a useful decomposition rather than an exhaustive one.

Each admits of several answers.

Delimitation can be explicit at both ends, where the user signals start and signals stop. It can be explicit then physical: the user starts by pressing and stops by releasing. It can be explicit then inferred, where the user starts and silence ends it. Or it can be inferred at both ends, with a wake word to begin and silence to close. That last cell is worth marking, because it is where smart speakers live, and `ambient.md` argues it carries a cost that has nothing to do with how well it works.

Feedback can be deferred, showing nothing until the end, or continuous, showing text as it resolves. Continuous splits further, because a recognizer's early guesses are revisable, so you must decide whether to display text you may have to retract. That sub-choice is what makes continuous feedback expensive to implement well, and it is why most products that stream text into a panel do not stream it into your document.

Delivery can be a single atomic insertion, writing to the clipboard and simulating a paste. It can be character-by-character synthesis, typing the text out as keystrokes. It can be replacement in place, using the accessibility API to overwrite a selection. Or it can be no insertion at all, putting the text in a window and letting the user take it.

## 3. Modes are bundles

Now re-derive the taxonomy from the axes.

Push-to-talk is delimitation by physical hold, feedback deferred, delivery by single insertion. Dictate is delimitation by explicit toggle, feedback continuous, delivery incremental.

They are two corners of a space that has more corners than that, and the corners they occupy differ on all three axes at once. This explains why they feel so unalike and why the difference seems fundamental: nothing varies a little between them. Everything varies together.

Nothing forces the bundling. Delimitation by physical hold is compatible with deferred or continuous feedback. Toggle delimitation is compatible with either. The bundles are conventions inherited from where each mode came from. Push-to-talk descends from half-duplex radio and gaming voice chat, where the concern was an open microphone in a shared channel. Dictate descends from Dragon and medical transcription, where sessions ran for minutes and a user who could not watch the transcript accumulate had no way to catch a failure before losing ten minutes of speech.

Those origins explain the correlations. They do not license treating them as necessary.

The decisive evidence against the taxonomy is that uttr occupies a third cell and nobody has a name for it. uttr delimits by explicit toggle: press to start, press again to stop. It defers feedback entirely. It delivers in one atomic insertion. That is push-to-talk's batch semantics with dictate's toggle ergonomics, and it is neither mode. Call it *toggle-to-talk*.

A taxonomy with a populated, unnamed, unremarkable third category was never a taxonomy. It is a pair of case studies that got promoted.

## 4. Three ways to arrive at a point in the space

If modes are points and the axes are coordinates, the interesting question becomes how a builder ends up at one point rather than another.

There are three routes, and the third is why this note exists.

**Outside-in.** Begin with the use case. Decide who is speaking, how long their utterances run, what it costs them when the tool is wrong. Derive constraints from that, and let the constraints select a point. This is the textbook method, and it is what design processes claim to do.

**Inside-out.** Begin with the axes. Enumerate the space, discard the incoherent combinations, and only then ask which of the survivors serves a use case worth serving. This is less common and often more generative, because it surfaces cells nobody thought to want. A mode delimited by silence and delivered atomically, for instance, which no product in the category advertises and which may be the best answer for short utterances.

The two routes are not guaranteed to converge. Outside-in tends to find the point that serves the use case you started from; inside-out tends to find points you had not considered, which is its value and also its risk.

**Affordance-driven.** Do not choose at all. Build the thing, and at each axis take whatever the platform and the libraries hand you for free. The point you land on is the sum of your dependencies' defaults.

## 5. The case study is this repository

uttr arrived at toggle-to-talk by the third route, and the mechanism is legible in three places in the source.

**Delimitation.** Global hotkeys on macOS are registered through Carbon's `RegisterEventHotKey`. You hand the window server a key combination and it calls you back on a match. In `HotkeyManager.swift`, uttr installs a handler for exactly one event type: `kEventHotKeyPressed`. Key-down.

Carbon will also deliver `kEventHotKeyReleased` for the same registration, so the release was always available. Nobody asked for it, and there is no reason to ask unless you already know you want it. This is the weaker and more accurate version of the story: the platform did not foreclose push-to-talk. It supplied key-down first, and key-down alone is enough to build something that works, so the second event type was never reached for.

What key-down alone gives you cheaply is counting presses. First press starts, second press stops. Toggle is not the *only* thing constructible from key-down — a press could start a recording terminated by a timer, or by silence, and silence termination is in fact uttr's own next planned mode — but it is the cheapest, and it is what you land on when you are not treating the question as a question.

**Feedback.** `AudioRecorder` builds an `AVAudioEngine`, installs a tap, and writes every buffer into an `AVAudioFile` on disk. When recording stops, `stopRecording()` returns a `URL`, and `FluidAudioProvider.transcribe(audioFileURL:)` hands that whole file to the recognizer.

This is the obvious way to record audio on Apple platforms, and it is what the framework is shaped to do. But a file is a completed thing. You cannot transcribe half of a file still being written, so the transcript cannot exist until the recording is over, so there is nothing to show the user in the meantime. Deferred feedback follows from choosing a file, and the file was chosen on other grounds.

**Delivery.** `PasteManager` saves the current clipboard, writes the transcript to it, synthesizes ⌘V through a `CGEvent`, and restores the old clipboard half a second later.

Clipboard-and-paste is the standard technique and works everywhere without per-application knowledge. Look at its shape, though: it borrows a global resource, uses it, and gives it back. That borrow-and-return can happen once per transcript. There is no coherent way to run it repeatedly as text streams in, because you would be seizing the user's clipboard continuously and pasting into their document over and over. Single atomic delivery falls out of the mechanism.

Three axes. Three answers, each at the simplest end of its range. None chosen; all inherited.

## 6. In defence of the third route

It would be easy to read the previous section as a diagnosis. Reading it that way is worse than not noticing at all.

Affordance-driven design produced a good product. uttr is coherent, it is small, and the three decisions fit together as though someone had planned them. In a sense someone did. The affordances of a well-designed platform are themselves coherent, because Apple's audio stack, its event system, and its pasteboard were designed by people who shared assumptions about what applications do. A builder taking the path of least resistance through all three inherits that coherence for free.

This is also how most good small software gets made. Deriving every decision from first principles before writing anything produces less software, and often worse software, because the derivations happen in ignorance of what the platform actually rewards.

A reader who knows Sarasvathy's work on **effectuation** will recognise the shape. Her distinction is between causation, where you take a goal as given and select among means to reach it, and effectuation, where you take the means at hand as given and imagine which ends are reachable. The effectual entrepreneur starts from the bird in hand: who I am, what I know, whom I know. The artifact emerges from available means rather than from a specified goal, and this describes what successful founders do rather than diagnosing a failure to plan.

The parallel is worth taking seriously. Affordance-driven design is effectuation applied to software: the libraries are the bird in hand, and the product that emerges is the one those means made cheap.

The parallel breaks at one joint. Sarasvathy's effectuator *chooses* to work from means. It is a deliberate stance, adopted knowingly, and it can be set down when circumstances change. The affordance-driven builder has usually not adopted a stance at all. There was no moment of deciding to let Carbon determine the delimitation model; there was a moment of registering a hotkey and moving on.

The difference shows up in what happens next. The same product may come out either way, but only one of the two builders can revise it deliberately, because you cannot revisit a decision you do not know you made.

## 7. What it costs, and when the bill arrives

Inherited design is free until you want something the affordances do not hand you. Then it presents as resistance nobody can explain.

The symptom is a feature that ought to be small and turns out to be tangled. Someone proposes push-to-talk. It is one gesture; how hard can it be? In this particular case the answer is that it is not hard at all, because the release event was there the whole time. What is hard is *knowing that* — and, more to the point, knowing why nobody had asked, and whether the answer generalises to the next question. The resistance is not in the platform. It is in the absence of a map of your own decisions.

This is what naming the axes buys. Not new capabilities, since the capabilities were mostly available. It converts inherited defaults into visible decisions. After the exercise, "uttr is toggle-to-talk" stops describing how the app behaves and becomes a statement about three specific positions, each of which can be examined, defended, or reversed on its own.

The map is worth having for a second reason. Name the axes and you can locate other products on them, and the field stops being a set of brands with opinions and becomes a space with coordinates. Superwhisper and Wispr Flow both sit at continuous feedback with post-processed delivery; macOS Dictation sits at continuous feedback with incremental insertion and no transformation. Reading off the coordinates tells you which differences between them are structural and which are styling.

## 8. Where the map fails

Two failures, and the second is the more interesting.

**The map has a hole exactly where the competition is.** The axes above have no coordinate for transformation. Whether a language model sits between the recognizer and the insertion point is the single most commercially salient difference between uttr and the products it gets compared to, and this scheme is forced to classify it as packaging. That is circular, since the scheme defines depth as representability within itself. The companion note argues that transformation deserves an axis of its own and that uttr's own best use case is the one that most needs it. A map drawn by the builder of one of the products it charts will tend to have this shape, and noticing the tendency is not the same as escaping it.

There is a related indictment the map does produce, to its credit. uttr's cell is a poor fit for long-form composition, and the delivery choice is what forecloses the improvement: atomic insertion cannot be made incremental without changing mechanism, so there is no gradual path from where uttr is to where a long-form tool needs to be. `MenuBarIconManager` still carries a `.transforming` state that nothing calls, left over from an ambition the delivery axis cannot currently support. The vestige is a fossil of a choice the app made without knowing it was closing a door.

**The axes are not independent.** Everything above treats them as free-varying. They are not, and there are two grades of coupling worth separating, because an earlier version of this section conflated them.

The weak kind is vendor packaging. uttr's next mode terminates recording on silence rather than on a second keypress: delimitation by inference, holding the other two fixed. On paper a pure move. The library offers two implementations — `VadManager`, which runs voice-activity detection and nothing else in about a megabyte, and `StreamingEouAsrManager`, which does end-of-utterance detection *and* transcribes as it goes, apparently more capability for the same effort. But the latter runs Parakeet EOU at 120M parameters against the 600M model uttr uses today, roughly 5% word error on LibriSpeech test-clean against 1.69%. So the choice of delimitation mechanism gets settled by asking whether you want live text on screen, which is a feedback question.

Two caveats keep this example from proving as much as it seems to. The benchmark is read audiobook prose, and the companion note argues at length that the content which actually breaks recognizers is nothing like LibriSpeech, so the ratio is indicative rather than decisive. And nothing structural ties utterance detection to a small ASR model; FluidAudio bundled them. That makes this another instance of section 5's subject — an affordance shaping a decision — rather than a new phenomenon.

The strong kind is structural, and `ambient.md` found it independently while arguing about something else. Terminating on silence removes a keypress but adds a monitoring burden: a user who cannot predict when the cutoff will fire has to watch for it. Making the mode tolerable therefore requires changing what the user sees during recording, which is a move on the feedback axis, forced by a move on the delimitation axis, with no vendor involved. Two notes reasoning from different premises arrived at the same coupling, which is better evidence than either provides alone.

So the honest conclusion is that unbundling buys less than it appears to. It does not buy free variation along independent dimensions. It buys legible coupling in place of inherited coupling: the constraints remain, but they surface as arguments you can have rather than resistance you cannot name.

That is worth the trouble. It should be claimed accurately, though. The axes are a map, they are incomplete in a way that flatters their author, and maps flatten adjacencies the territory keeps.

---

*Companion notes: `speech-and-typing.md` on which utterances belong to which input channel, and on the fourth axis this note is missing; `ambient.md` on the principle behind several of the decisions described here.*
