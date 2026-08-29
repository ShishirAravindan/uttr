# Ambient

*On a word that has been ruined, a test that might rescue it, and whether this application passes.*

---

## 1. Weiser's claim

In September 1991, Mark Weiser opened an article in *Scientific American* with a sentence that has been quoted so often it has stopped being read:

> The most profound technologies are those that disappear. They weave themselves into the fabric of everyday life until they are indistinguishable from it.

Weiser's example was writing. Written language is everywhere — on packaging, on signs, on the sides of vehicles — and it is so thoroughly absorbed that we do not experience ourselves as *using a technology* when we read a street name. It has left the foreground permanently.

He and John Seely Brown later sharpened this into **calm technology**: technology that moves fluidly between the centre and the periphery of a person's attention, and which spends most of its time in the periphery. The periphery, in their usage, is not "unnoticed." It is *attended without being attended to* — the way you are aware of the temperature of a room, or of a car's engine note, and the way that awareness becomes explicit the moment something changes.

That is the intellectual heritage of the word "ambient," and it is a demanding one.

## 2. The word has been ruined

Thirty years on, "ambient computing" is used to mean an always-on microphone in a kitchen, or a display that never turns off, or a wearable that collects telemetry continuously.

These are usually the *opposite* of what Weiser described. A device that listens all the time is not in your periphery; it is permanently in your awareness, precisely because you cannot forget it is there. The whole discourse about smart speakers — whether they are recording, what happens to the audio, whether to unplug one before a private conversation — is evidence that the technology has failed to become peripheral. You cannot stop thinking about it. That is the definition of central.

So "ambient" as a vibe is useless. If the word is to do any work, it needs a test.

## 3. A proposed criterion

Here is one. It is not Weiser's, but it is downstream of him and it has the advantage of being checkable:

> **A technology is ambient to the degree that it costs nothing when you are not using it.**

The move is to stop asking whether something is *visible* and start asking what it *charges*. Three costs matter, and the third is the one that is usually missed.

**Attention cost.** Does it occupy the centre of your attention while idle? Does it move, blink, notify, or otherwise recruit you when nothing has happened?

**Surface cost.** Does it take up space you would otherwise be using — screen area, a window, the focused application, a slot in your dock or your task switcher?

**Trust cost.** Do you have to *hold a belief* about it when you are not using it? Is there a proposition about its behaviour that you must keep in mind, or periodically re-examine, in order to be comfortable having it installed?

The third cost explains why "invisible" is the wrong criterion, and it explains the smart-speaker failure. It also produces an immediately clarifying result: **a keylogger is maximally invisible and minimally ambient.** It has no attention cost and no surface cost whatsoever. It is nonetheless something you would think about constantly, because using the machine would require continuously reaffirming a belief about what the software is doing with what you type. Invisibility and ambience come apart completely at this case, which is a good sign the criterion is picking out something real.

## 4. Three decisions, one principle

uttr has made three decisions that its author is fond of and has described as sharing an essence. They do — and the interesting claim is not that they are all restrained, but that each pays down a *different* one of the three costs. That is what makes them one principle applied thrice rather than three instances of good taste.

### The refusal to observe keystrokes

To detect a key *release* — and therefore to support push-to-talk, or modifier-only chords, or double-tap gestures — a macOS application must install an event tap or a global event monitor. Either one delivers every keystroke the user types, system-wide, to your callback. uttr does not do this, and has declined to, even though everything it would observe stays on the machine and never touches a network.

This is a pure trust-cost decision, and it is the sharpest illustration of the criterion, because on the other two costs the event tap is *free*. It draws nothing. It occupies nothing. It is completely undetectable in use.

What it costs is a belief. A user of a keystroke-observing uttr would have to hold, somewhere in the back of their mind, the proposition *this app can read everything I type, but it is local, so it is fine.* That proposition is true. It is also a thought, and it is a thought you have to keep having. Ambient technology does not require you to keep having a thought about it.

The refusal buys no functionality. It buys the absence of a required belief, which is the whole of what it was meant to buy.

### The menu bar as the only surface

uttr has no window in normal operation. It is an accessory application; it does not appear in the dock or the task switcher; its entire interface while working is one status item.

The obvious reading is that this is a surface-cost decision, and it is. But the subtler point is about *which* surface. The macOS menu bar is the operating system's designated periphery — it is the one region of the screen users have been trained, over decades, to glance at without focusing on. Weiser's periphery is not a matter of size; it is a matter of being attended without being attended to, and the menu bar is a channel where that habit already exists.

Building there is not merely economical. It is borrowing an established peripheral channel instead of constructing a new one, which no application can do on its own — a floating panel is a new thing demanding new attention, however small you make it.

There is a corollary decision in the source worth noticing. `MenuBarIconManager` deliberately *keeps* uttr's icon during recording and breathes it with a slow opacity pulse, rather than hiding it and letting the system's orange microphone dot signal the state. The comment explains that the system indicator collapses into an anonymous dot when the menu bar is crowded. Read against the criterion: this is a refusal to abandon a peripheral channel you already own for one you do not control. The pulse is not decoration; it is the app keeping its position in the periphery rather than being evicted into ambiguity.

### The Neural Engine

Running Parakeet on the Apple Neural Engine, entirely on-device, reads as a performance decision. Under the criterion it is an attention-cost decision, and it operates through two mechanisms.

The first is that **a machine that changes behaviour is announcing itself.** A fan spinning up, a laptop growing warm, other applications becoming sluggish — these are all ways for software to leave the periphery without displaying anything. The ANE is a coprocessor with low power draw and, crucially, low contention: it is not where the rest of the system is working. Transcription happens without the machine acting differently, which is what allows the tool to remain unnoticed while it runs.

The second is that on-device inference means the application has **no state outside the machine**. There is no account, no history on a server, no question of retention policy. This is a trust cost that has been driven to zero rather than merely made acceptable — and the difference matters, because an acceptable trust cost is one you have to re-evaluate whenever the terms change, while a zero one is one you never think about again.

Three costs, three decisions, one principle. The consistency is not accidental and it is not merely aesthetic.

## 5. The principle keeps producing answers

A stronger test of whether a principle is real, rather than a story told afterwards, is whether it generates decisions you had not already made. This one does — several conclusions reached independently in design discussion turn out to be corollaries.

**Do not design around cheap failures.** If uttr pastes into the wrong application because focus moved, the user presses ⌘Z and tries again. Adding a confirmation step, or a review panel, to prevent this would be a mistake — and the criterion says exactly why. A confirmation dialog converts a peripheral interaction into a central one, every single time, in order to mitigate a failure that costs one keystroke. Guard rails are attention costs charged on every use. The right test is whether a failure is reversible by a keystroke the user already knows; where it is, the correct handling is none.

**Modulate an existing signal before adding a new one.** When the question arose of showing the user more about what the tool was doing, the first instinct was a floating panel with a level meter. The better answer was to change the character of the pulse that already exists. Same channel, no new surface, no new attention charge. This generalises: an ambient interface grows in *resolution*, not in *area*.

**Return borrowed resources exactly.** The clipboard belongs to the user. uttr borrows it to perform a paste and restores it afterwards. Read as an ambient matter, this is not politeness — it is the difference between a tool that leaves no trace and one whose side effects you must remember. (The current implementation restores on a fixed half-second timer, which can lose a copy the user makes inside that window. That is a real defect, and it is a defect *of this principle* rather than merely a bug: it is the one place where the tool's operation leaves damage the user cannot undo.)

**Automation is not the same as ambience, and can be its enemy.** This is the most interesting thing the principle produces, because it cuts against an assumption.

Ending a recording automatically on silence removes a required action. That looks like an unambiguous ambient improvement: fewer keystrokes, less to do. But it replaces a task with a *monitoring burden*. If the user cannot predict when the cutoff will fire, they must watch for it — and watching is exactly the attention cost the principle is trying to eliminate. Automatic behaviour that is not predictable is anti-ambient, and it can easily be worse than the manual action it replaced.

The resolution is legibility. If the pulse visibly dims as silence accumulates and snaps back the instant speech resumes, the user can *feel* the timer without reading one. The mechanism becomes predictable, the monitoring burden disappears, and the automation becomes a genuine ambient gain rather than a trade of one cost for another.

That is a design requirement derived from the principle, not decorated with it — and it was not obvious in advance.

## 6. Where the claim should be limited

The author's own framing was that this might be baby steps rather than a realised vision. That is the right posture, and the honest accounting has four entries.

**First launch is maximally central.** uttr downloads a 600 MB model on first use, shows a loading state, and blocks recording until it is ready. Nothing about this is peripheral. It is defensible — it happens once — but it should not be described as ambient, and it is the part of the experience most in need of care.

**Permissions are an unavoidable central moment.** Microphone and Accessibility both require the user to leave the app, navigate System Settings, and grant explicitly. The app has done what it can to soften this, but the moment exists and cannot be designed away.

**Delivery is not peripheral and should not be.** The paste writes into the user's document, which is the most central object on their screen. This is worth stating plainly because it clarifies the claim: ambience is a property of the *instrument*, not of the effect. A tool can be entirely peripheral and produce a loud, consequential, central result. That is the correct shape, not a compromise — a peripheral instrument whose output was also peripheral would be a tool that did nothing.

**Failure is central by design.** When transcription fails, the icon flashes an error state and a notification fires. This is a deliberate exit from the periphery, and it is right. Calm technology is not silent technology; Weiser's point was about moving *between* centre and periphery, and something that never comes to the centre cannot tell you when it has broken.

So: three decisions genuinely instantiate a coherent principle, and the principle keeps producing correct answers to new questions. The rest of the experience does not yet live up to it. Both things are true, and the second is the more useful one to hold onto.

## 7. What ambience is actually for

It would be easy to treat all of this as taste — a preference for restraint, a minimalist aesthetic, an argument about how software should feel.

It is not, and the reason connects to the other note in this directory.

The strongest case for speech input is the **unformed thought**: the half-considered observation, the thing you would not have bothered to type. But a thought like that is small, and its value is small, and it will only ever get captured if the cost of capturing it is *smaller still*. If speaking a passing idea requires opening an application, selecting a mode, watching a panel, and dismissing it afterwards, nobody will do it — not because the overhead is large in absolute terms, but because it exceeds the worth of the thought.

Ambience is what makes a small utterance worth making. That is the entire argument. The menu bar, the Neural Engine, the refusal to watch the keyboard, the single atomic paste that hands you back to what you were doing — these are not restraint for its own sake. They are what drives the cost of reaching for the tool low enough that its best use case survives contact with reality.

A tool you must attend to is a tool you will only use for things worth attending to. The whole point is the other things.

---

## References

- Weiser, M. (1991). *The Computer for the 21st Century.* Scientific American, 265(3).
- Weiser, M. & Brown, J. S. (1996). *The Coming Age of Calm Technology.*

*Companion notes: `axes-and-modes.md` on the structure of choices in this category; `speech-and-typing.md` on which utterances speech is actually for.*
