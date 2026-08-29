# Ambient

*What the word should mean if it is to do any work, and whether this application earns it.*

---

## 1. Weiser's claim

In September 1991, Mark Weiser opened an article in *Scientific American* with a sentence quoted so often it has stopped being read:

> The most profound technologies are those that disappear. They weave themselves into the fabric of everyday life until they are indistinguishable from it.

Weiser's example was writing. Written language is everywhere, on packaging and signs and the sides of vehicles, and it is so thoroughly absorbed that we do not experience ourselves as using a technology when we read a street name. It has left the foreground permanently.

He and John Seely Brown later sharpened this into **calm technology**: technology that moves fluidly between the centre and the periphery of a person's attention, and that spends most of its time in the periphery. The periphery, in their usage, does not mean unnoticed. It means attended without being attended to, the way you are aware of the temperature of a room or a car's engine note, and the way that awareness becomes explicit the moment something changes.

That is the heritage of the word "ambient," and it is a demanding one.

## 2. The word has been ruined

Thirty years on, "ambient computing" is used to mean an always-on microphone in a kitchen, or a display that never turns off, or a wearable collecting telemetry continuously.

These are usually the opposite of what Weiser described. A device that listens all the time sits permanently in your awareness, because you cannot forget it is there. The entire public conversation about smart speakers, about whether they are recording and what happens to the audio and whether to unplug one before a private conversation, is evidence that the technology failed to become peripheral. You cannot stop thinking about it. That is what central means.

So "ambient" as a mood is useless. If the word is to do work, it needs a test.

## 3. A proposed criterion, and its weaknesses

Here is one. It is not Weiser's, but it descends from him and has the advantage of being mostly checkable:

> **A technology is ambient to the degree that it costs nothing outside the moments you intend to use it.**

The move is to stop asking whether something is visible and start asking what it charges. Three costs matter.

**Attention cost.** Does it recruit you when nothing has happened? Does it move, blink, sound, or notify while idle, or make the machine behave differently while working?

**Surface cost.** Does it occupy space you would otherwise use: screen area, a window, the focused application, a slot in the dock, a folder in your home directory?

**Trust cost.** Must you hold a belief about it while you are not using it? Is there a proposition about its behaviour you have to keep in mind, or periodically re-examine, to stay comfortable having it installed?

Two admissions before this goes any further, because the criterion is weaker than it first looks.

The first is about scope. The original phrasing was "costs nothing when you are not using it," and that version is cleaner but wrong, because it excuses everything a tool does while running. A transcription that spins the fans is a cost, and it happens squarely during use. The clause has to be *outside the moments you intend to use it*, which is vaguer and admits argument about what counts as intended use. That vagueness is the price of covering the cases that matter.

The second is about checkability. Attention cost and surface cost can be observed by someone else watching you work. Trust cost cannot. It is a claim about what a user has to keep in mind, and there is no instrument for it beyond introspection and analogy. It is also the cost this note leans on hardest. A reader who rejects trust cost as unmeasurable will find the rest of the argument correspondingly soft, and that objection cannot be fully answered.

What can be offered is a case that isolates it. **A keylogger is maximally invisible and minimally ambient.** It has no attention cost and no surface cost whatsoever, and it is nonetheless something you would think about constantly, because using the machine would mean continuously reaffirming a belief about what the software does with what you type. Invisibility and ambience come apart completely at that case, which is some evidence the third column is picking out something real even if it cannot be measured.

## 4. Three decisions

uttr has made three decisions its author is fond of and has described as sharing an essence. They do share one, though the shape of the sharing is messier than a table would suggest.

### The refusal to observe keystrokes

uttr does not install a `CGEvent` tap or a global `NSEvent` keyboard monitor. Either one delivers every keystroke typed anywhere on the system to the application's callback, and uttr has declined to take that capability even though everything it would observe stays on the machine.

One correction first, because the claim is easy to inflate and the inflated version is false. Detecting a key *release* does not require a tap. Carbon's `RegisterEventHotKey` will deliver `kEventHotKeyReleased` for the combination you registered, so push-to-talk is reachable without observing anything else. What genuinely requires the stream is the class of gestures that have no registered combination to hang off: modifier-only chords like hold-right-⌘, and double-tap detection. Those are real losses and they are the honest extent of the sacrifice.

With that narrowed, the decision is still instructive, because on the other two costs a tap is free. It draws nothing. It occupies nothing. It is undetectable in use.

What it costs is a belief. A user of a keystroke-observing uttr would have to hold, somewhere in the back of their mind, the proposition *this app can read everything I type, but it is local, so it is fine.* The proposition is true. It is also a thought, and one you have to keep having.

An objection deserves a hearing here, and it is a good one. uttr already requires Accessibility permission, granted through the same System Settings pane, in order to synthesize ⌘V. A user therefore already holds a belief of the same family: *this app can inject keystrokes into any application.* That is a write capability rather than a read one, and arguably the more alarming direction. If the objection stands, the refusal is calibrated to intuition rather than to capability, which would make it theatre.

Two distinctions rescue it, and they should be stated rather than assumed. The first is *invoked versus continuous*: uttr's write capability fires only when the user presses the hotkey, so its exercise is bounded by an action the user takes deliberately, whereas a tap runs whenever the machine is on. The second is *scoped versus total*: the paste writes one string the user just dictated into the application they are looking at, while a tap observes everything typed everywhere, including in applications uttr has no business knowing about. The permissions look similar in System Settings and are not similar in what they let the software know.

The refusal buys no functionality. It buys the absence of a required belief, which is what it was for.

### The menu bar as the only surface

uttr has no window in normal operation. It is an accessory application; it does not appear in the dock or the task switcher; its entire interface while working is one status item.

The obvious reading is surface cost, and that reading is correct. The subtler point concerns *which* surface. The macOS menu bar is the operating system's designated periphery, the one region of the screen users have been trained over decades to glance at without focusing on. Weiser's periphery is not a matter of size but of being attended without being attended to, and the menu bar is a channel where that habit already exists.

Building there borrows an established peripheral channel instead of constructing a new one, which no application can do on its own. A floating panel is a new thing demanding new attention, however small you make it.

A corollary decision in the source is worth noticing. `MenuBarIconManager` deliberately keeps uttr's icon during recording and breathes it with a slow opacity pulse, rather than hiding it and letting the system's orange microphone dot signal the state. The comment explains that the system indicator collapses into an anonymous dot when the menu bar is crowded. Read against the criterion, this refuses to abandon a peripheral channel you own for one you do not control. The pulse holds the app's position in the periphery rather than letting it be evicted into ambiguity.

### The Neural Engine

Running Parakeet on the Apple Neural Engine, entirely on-device, reads as a performance decision. Under the criterion it pays down two costs at once, and the fact that it pays two is worth stating plainly rather than tidying away.

The attention argument is that a machine which changes behaviour is announcing itself. Fans spinning up, a laptop growing warm, other applications turning sluggish: these are all ways for software to leave the periphery without displaying anything. The ANE is a coprocessor with low power draw and, more importantly, low contention, since it is not where the rest of the system is working. Transcription happens without the machine acting differently.

The trust argument is that on-device inference leaves the application with no state outside the machine. No account, no history on a server, no retention policy. That drives a trust cost to zero rather than making it acceptable, and the difference matters: an acceptable trust cost has to be re-evaluated whenever the terms change, while a zero one is never thought about again.

It would be neater if each decision paid down exactly one cost, and an earlier draft of this note claimed that. It is not true, and the tidiness was doing argumentative work it had not earned. What actually unifies the three is not a partition of the cost table but a common move: **in each case a capability was available, would have been invisible in use, and was declined or constrained because of what it would have charged while nobody was using it.** That is a weaker claim than a 3×3 grid and it is the one the evidence supports.

## 5. The principle keeps producing answers, with a caveat about what that proves

A principle is more credible if it generates decisions rather than decorating them. This one has generated several. The caveat has to come first, though: most of what follows was decided before the principle was articulated, and recognising a decision as a corollary after the fact is retrodiction. Retrodiction is weak evidence. It shows the decisions are consistent with each other, which is worth something, and it does not show the principle did any work.

Only the last item below was genuinely derived, and even that rests on a claim about the author's own sequence of thought, which no reader can check.

**Do not design around cheap failures.** If uttr pastes into the wrong application because focus moved, the user presses ⌘Z and tries again. Adding a confirmation step or a review panel to prevent this would convert a peripheral interaction into a central one, every single time, to mitigate a failure costing one keystroke. Guard rails are attention costs charged on every use. The test is whether a failure is reversible by a keystroke the user already knows; where it is, the right handling is none.

**Modulate an existing signal before adding a new one.** When the question arose of showing the user more about what the tool was doing, the first instinct was a floating panel with a level meter. The better answer was to change the character of the pulse that already exists. Same channel, no new surface. An ambient interface should grow in resolution rather than in area.

**Return borrowed resources exactly.** The clipboard belongs to the user. uttr borrows it to perform a paste and restores it afterwards, which is the difference between a tool that leaves no trace and one whose side effects you have to remember. The current implementation restores on a fixed half-second timer and can therefore lose a copy the user makes inside that window. That is a defect of this principle rather than an ordinary bug, since it is the one place where the tool's operation damages something the user cannot undo.

**Automation is not ambience, and can be its enemy.** This is the item that was actually derived, and it cuts against an assumption.

Ending a recording automatically on silence removes a required action, which looks like an unambiguous improvement. But it replaces a task with a monitoring burden. A user who cannot predict when the cutoff will fire has to watch for it, and watching is exactly the attention cost the principle exists to eliminate. Automatic behaviour that is unpredictable can easily be worse than the manual action it replaced.

The resolution is legibility. If the pulse visibly dims as silence accumulates and snaps back the instant speech resumes, the user feels the timer without reading one, the behaviour becomes predictable, and the monitoring burden disappears.

Note what that argument implies for the companion note. `axes-and-modes.md` treats silence termination as a clean move along the delimitation axis alone. It is not: making it ambient requires changing what the user sees, which is a move on the feedback axis. The two notes reached that coupling from opposite directions, which is the best evidence either of them offers that the coupling is structural rather than an artifact of one vendor's SDK.

## 6. Where the application does not pass

The author's own framing was that this might be baby steps rather than a realised vision. That is the right posture, and an honest accounting has more entries than the pleasant ones.

**Sound is charged on every use, and it broadcasts.** `NotificationManager` plays a sound when recording starts, another when it stops, and another on success. Sound is a legitimate peripheral channel and Weiser and Brown discuss it as one, so this is not obviously wrong. But it is the one channel that leaves your machine and enters the room, and it cannot be turned off, since there is no setting for it. An application whose companion argument makes much of speech broadcasting your content to everyone present should notice that its own feedback broadcasts your tool use to everyone present. Three sounds per transcription, in an open-plan office, is not peripheral to the people around you.

**History is written into user space.** `HistoryManager` stores transcripts in `~/Documents/History/`, while settings live in `~/Library/Application Support/uttr/`. Documents is a folder the user looks at. Putting files there is a surface cost, taken for no reason, and probably by accident.

**First launch is maximally central.** uttr downloads a 600 MB model on first use, shows a loading state, and blocks recording until it is ready. Nothing about this is peripheral. It happens once, which is a defence, but it should not be described as ambient, and it is the part of the experience most in need of care.

**Permissions are an unavoidable central moment.** Microphone and Accessibility both require the user to leave the app and grant explicitly. The app softens this where it can. The moment exists and cannot be designed away.

**Delivery is not peripheral and should not be.** The paste writes into the user's document, the most central object on their screen. Stating this plainly clarifies the claim: ambience is a property of the instrument, not of the effect. A tool can be entirely peripheral and produce a loud, consequential result, and a peripheral instrument whose output was also peripheral would be a tool that did nothing.

**Failure is central by design.** When transcription fails, the icon flashes an error state and a sound plays. This is a deliberate exit from the periphery and it is right. Calm technology is not silent technology; Weiser's point concerned movement *between* centre and periphery, and something that never comes to the centre cannot tell you it has broken.

Three decisions instantiate a coherent principle. The first two entries above violate it, one of them in a way that undercuts an argument made elsewhere in this directory. Both things are true, and the second is more useful to hold onto.

## 7. What ambience is for

All of this could be read as taste: a preference for restraint, a minimalist aesthetic, an argument about how software ought to feel.

The reason it is not connects to the companion note. The strongest case for speech input is the unformed thought, the half-considered observation you would not have bothered to type. A thought like that is small, its value is small, and it will only get captured if the cost of capturing it is smaller still. If speaking a passing idea means opening an application, selecting a mode, watching a panel and dismissing it afterwards, nobody will do it. The overhead is not large in absolute terms; it simply exceeds the worth of the thought.

Ambience is what makes a small utterance worth making. The menu bar, the Neural Engine, the declined capability, the single paste that hands you back to what you were doing — these lower the cost of reaching for the tool until its best use case survives contact with an ordinary working day.

Which sets the standard the two entries in section 6 fail. A tool that pings three times and leaves files in your Documents folder has not finished becoming peripheral, whatever its architecture diagram says.

---

## References

- Weiser, M. (1991). *The Computer for the 21st Century.* Scientific American, 265(3).
- Weiser, M. & Brown, J. S. (1996). *The Coming Age of Calm Technology.*

*Companion notes: `axes-and-modes.md` on the structure of choices in this category; `speech-and-typing.md` on which utterances speech is actually for.*
