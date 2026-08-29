# Axes and Modes

*On why speech-to-text products appear to come in two kinds, why that appearance is misleading, and what it costs to have never noticed.*

---

## 1. The apparent taxonomy

Ask anyone who has used more than one transcription tool how such tools work, and you will get back a taxonomy with two entries.

There is **push-to-talk**: you hold a key, you speak, you release, and the text appears. And there is **dictate**: you press a key once, the app begins listening, words appear as you say them, and you press again to stop.

The two feel genuinely different to use, and the difference seems fundamental rather than incidental. One is a gesture you perform with your body; the other is a session you enter and leave. One gives you nothing until you are finished; the other narrates itself. Products advertise which one they are. Users have preferences between them.

So it looks like a taxonomy — like a fact about the domain, the way "cars have automatic or manual transmissions" is a fact about cars.

It is not. It is a coincidence that has been mistaken for a category, and the mistake is expensive in a specific way: it hides the fact that you have already made design decisions you do not remember making.

## 2. What any transcription tool must do

Start further back, from the structure of the problem rather than from the products.

A tool that turns speech into text in a running computer must do three things, and it is difficult to construct one that does fewer.

**It must know which audio to transcribe.** A speech recognizer does not consume an infinite stream and emit an infinite stream; it consumes a *span*. Some boundary must mark where the interesting audio starts and where it ends. This is not a design flourish — it is a precondition. Call this **delimitation**.

**It must decide when the user learns what it heard.** The transcript comes into existence at some moment; the user perceives it at some moment; these need not be the same moment. There is necessarily a gap, and the size of the gap is a choice. Call this **feedback**.

**It must put the text somewhere.** The text is useless inside the app. It has to arrive in the document, the message box, the terminal — somewhere the user was already working. There is always a mechanism, and mechanisms differ. Call this **delivery**.

Three requirements: bound the input, reveal the result, place the output. Begin, compute, deliver. That is why there are three and not seven — they are not a list someone brainstormed, they are the joints of the problem.

Each admits of several answers.

Delimitation can be *explicit at both ends* (the user signals start and signals stop), *explicit then physical* (the user starts by pressing and stops by releasing), *explicit then inferred* (the user starts, and silence ends it), or *inferred at both ends* (a wake word begins it, silence ends it).

Feedback can be *deferred* (nothing until the end) or *continuous* (text as it resolves), and continuous itself splits — the recognizer's early guesses are revisable, so you must decide whether to show text you may have to retract.

Delivery can be *a single atomic insertion* (write to the clipboard, simulate a paste), *character-by-character synthesis* (type it as keystrokes), *replacement in place* (use the accessibility API to overwrite a selection), or *no insertion at all* (put it in a window and let the user take it).

## 3. Modes are bundles

Now re-derive the taxonomy from the axes.

**Push-to-talk** is: delimitation by physical hold, feedback deferred, delivery by single insertion. **Dictate** is: delimitation by explicit toggle, feedback continuous, delivery incremental.

They are not two points on a line. They are two *corners* of a space with more corners than that — and the corners they occupy differ on all three axes at once. That is precisely why they feel so unalike, and precisely why the difference seems fundamental: nothing varies a little between them, everything varies together.

But nothing forces the bundling. Delimitation by physical hold is compatible with continuous feedback. Toggle delimitation is compatible with deferred feedback. The bundles are conventions inherited from where each mode came from — push-to-talk from half-duplex radio and gaming voice chat, where the concern was an open microphone in a shared channel; dictate from Dragon and medical transcription, where sessions ran for minutes and a user who could not see the transcript accumulating had no way to catch a failure before losing ten minutes of speech.

Those origins explain the correlations. They do not justify treating them as necessary.

The decisive evidence that the taxonomy was never a taxonomy is that **uttr occupies a third cell and nobody has a name for it.** uttr delimits by explicit toggle — press to start, press again to stop. It defers feedback entirely. It delivers in one atomic insertion. That is push-to-talk's batch semantics with dictate's toggle ergonomics, and it is neither mode. Call it *toggle-to-talk*.

A taxonomy with a populated, unnamed, and unremarkable third category is not a taxonomy. It is a pair of case studies that got promoted.

## 4. Three ways to arrive at a point in the space

If modes are points and the axes are the coordinates, the interesting question becomes: how does a builder end up at one point rather than another?

There are three routes, and the third is the one this note exists to name.

**Outside-in.** Begin with the use case. Decide who is speaking, how long their utterances are, what it costs them when the tool is wrong. Derive constraints from that, and let the constraints select a point. This is the textbook method, and it is what design processes claim to do.

**Inside-out.** Begin with the axes. Enumerate the space, discard the combinations that are incoherent, look at what remains, and only then ask which of the surviving points serves a use case worth serving. This is less common and often more generative, because it surfaces cells nobody thought to want — a mode delimited by silence and delivered atomically, for instance, which no product in the category advertises and which may be the best answer for short utterances.

Both routes arrive somewhere defensible. They travel in opposite directions and meet in the middle.

**Affordance-driven.** Do not choose at all. Build the thing, and at each axis take whatever the platform and the libraries hand you for free. The point you land on is the sum of your dependencies' defaults.

## 5. The case study is this repository

uttr arrived at toggle-to-talk by the third route, and the mechanism is legible in three places in the source.

**Delimitation.** Global hotkeys on macOS are registered through Carbon's `RegisterEventHotKey`. You hand the window server a key combination and it calls you back on a match. In `HotkeyManager.swift`, uttr installs a handler for exactly one event type: `kEventHotKeyPressed`. Key-down. Carbon will also deliver `kEventHotKeyReleased`, but you have to ask, and there is no reason to ask unless you already know you want it.

With only key-down available, what can you build? You can count presses. First press starts, second press stops. Toggle is not a decision here — it is the *only* thing key-down alone can express. Push-to-talk is unreachable, because push-to-talk is a statement about a release.

**Feedback.** `AudioRecorder` builds an `AVAudioEngine`, installs a tap, and writes every buffer into an `AVAudioFile` on disk. When recording stops, `stopRecording()` returns a `URL`, and `FluidAudioProvider.transcribe(audioFileURL:)` hands that whole file to the recognizer.

This is the obvious way to record audio on Apple platforms — it is what the framework is shaped to do. But a file is a *completed thing*. You cannot transcribe half of a file that is still being written, so the transcript cannot exist until the recording is over, so there is nothing to show the user in the meantime. Deferred feedback is not a decision either. It is downstream of choosing a file.

**Delivery.** `PasteManager` saves the current clipboard, writes the transcript to it, synthesizes ⌘V through a `CGEvent`, and restores the old clipboard half a second later.

Clipboard-and-paste is the standard technique, and it works everywhere without per-application knowledge. But look at its shape: it borrows a global resource, uses it, and gives it back. That borrow-and-return can happen *once* per transcript. There is no coherent way to run it repeatedly as text streams in — you would be seizing the user's clipboard continuously and pasting into their document over and over. Single atomic delivery is not a decision. It falls out of the mechanism.

Three axes. Three answers, each sitting at the simplest, most one-shot end of its range. None of them chosen; all of them inherited.

## 6. In defence of the third route

It would be easy to read section 5 as a diagnosis of a problem. It is not, and getting this wrong is worse than not noticing at all.

Affordance-driven design produced a good product. uttr is coherent, it is small, and the three decisions fit together as though someone had planned them — because in a sense someone did. The affordances of a well-designed platform are themselves coherent. Apple's audio stack, its event system, and its pasteboard were designed by people who shared assumptions about what applications do. A builder who takes the path of least resistance through all three inherits that coherence for free.

This is also, empirically, how most good small software gets made. The alternative — deriving every decision from first principles before writing anything — produces less software, and often worse software, because the derivations are made in ignorance of what the platform actually rewards.

The reader who has met Sarasvathy's work on **effectuation** will recognise the shape of this. Her distinction is between *causation* — given a goal, select among means to reach it — and *effectuation* — given the means at hand, imagine which ends are reachable. The effectual entrepreneur starts from the bird in hand: who I am, what I know, whom I know. The artifact emerges from available means rather than from a specified goal, and this turns out to be what successful founders actually do, rather than a failure to plan.

The parallel is real and worth taking seriously. Affordance-driven design *is* effectuation applied to software: the libraries are the bird in hand, and the product that emerges is the one those means made cheap.

But the parallel breaks at one joint, and the break is the whole point of this note.

Sarasvathy's effectuator **chooses** to work from means. It is a deliberate stance, adopted knowingly, and it can be set down when circumstances change. The affordance-driven builder usually does not know they have taken a stance at all. There was never a moment of choosing to let Carbon decide the delimitation model; there was a moment of registering a hotkey and moving on to the next thing.

Effectuation is affordance-driven design that knows its own name. The difference is not in the artifact — the same product comes out either way. The difference is in whether you can *revise* it, because you cannot revisit a decision you do not know you made.

## 7. What it costs, and when the bill arrives

Inherited design is free until you want something the affordances do not hand you. Then it presents as unexplained resistance.

The symptom is a feature that ought to be small and is not, for reasons nobody can articulate. Someone proposes push-to-talk. It is one gesture; how hard can it be? And the answer is that it is not hard at all — but only once you understand that the shape of the hotkey registration, made years ago in a file nobody thinks about, is load-bearing for the interaction model. Until you understand that, the difficulty has no explanation. It just feels like the codebase is fighting you.

This is what naming the axes buys. Not new capabilities — the capabilities were always available. What it buys is the conversion of **inherited coupling into visible decision**. After the exercise, "uttr is toggle-to-talk" stops being a description of how it behaves and becomes a statement about three specific choices, each of which can now be examined, defended, or reversed on its own.

The map is worth having for a second reason. Once you can name the axes, you can locate other products on them, and the field stops being a set of brands with opinions and becomes a space with coordinates. Superwhisper, Wispr Flow, macOS Dictation, Discord's push-to-talk overlay — each is a point, and once you can read off the coordinates you can see immediately which of their differences are deep and which are packaging.

## 8. A complication: the axes are not independent

Everything above treats the three axes as though they vary freely. They do not, and the discovery of this in practice is more instructive than the abstraction.

The case is concrete. uttr's likely next mode terminates recording on silence rather than on a second keypress — delimitation by inference, holding feedback and delivery fixed. On paper this is a pure move along one axis.

The library offers two ways to do it. `VadManager` runs Silero voice-activity detection: it answers "is someone speaking right now?" and nothing else, in about a megabyte. `StreamingEouAsrManager` does end-of-utterance detection *and* transcribes as it goes, in one object — apparently strictly more capability for the same integration effort.

But `StreamingEouAsrManager` runs a different model: Parakeet EOU at 120M parameters, against the 600M model uttr uses today. On LibriSpeech test-clean that is roughly 5% word error against 1.69% — three times the errors. Adopting it for delimitation means accepting a materially worse transcript, unless you run both models and discard one's output.

So the question "which delimitation mechanism?" cannot be answered on the delimitation axis. It is settled by asking whether you want live text on screen — a *feedback* question. If yes, the streaming manager's transcript is not waste and it earns its cost. If no, it is a worse model doing a job a one-megabyte detector does better.

A preference about what the user sees resolved a question about which neural network to load. Nothing in the abstraction predicted that.

The honest conclusion is not that the axes are wrong; it is that the win is smaller and different than it first appears. Unbundling does not give you free variation along independent dimensions. It gives you **legible coupling in place of inherited coupling**. The couplings are still there — they are properties of the tools and the physics, not of your ignorance — but they now show up as arguments you can have, rather than as resistance you cannot explain.

That is still worth the trouble. An argument you can have is a different kind of object from a difficulty you cannot name. But it should be claimed accurately: the axes are a map, and maps flatten adjacencies that the territory keeps.

---

*Companion notes: `speech-and-typing.md` on which utterances belong to which input channel; `ambient.md` on the principle that has been doing quiet work behind several of these decisions.*
