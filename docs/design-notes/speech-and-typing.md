# Speech and Typing

*On a study that is right, a slogan that is wrong, and the variable both of them miss.*

---

## 1. The displacement thesis

The current generation of dictation products does not sell itself as a convenience. It sells itself as a succession.

Wispr Flow's pitch is that you should stop typing — that the keyboard is a bottleneck you have been tolerating, and that voice removes it. The surrounding category speaks the same way: *your voice is faster than your fingers*, *think it, say it, done*, *the end of typing*. The framing is not that speech is a useful additional channel. It is that speech is the successor input, and the keyboard is a legacy device we happen not to have retired yet.

Call this the **displacement thesis**: that speech and typing compete for the same job, that speech wins, and that a rational user migrates.

It is worth taking seriously, because there is real evidence behind it and because the products built on it are good. It is also wrong, and interestingly wrong — the way it fails tells you what these tools are actually for.

## 2. The evidence, at its strongest

In 2016 a team from Stanford, the University of Washington and Baidu published *Speech Is 3x Faster than Typing for English and Mandarin Text Entry on Mobile Devices*. Thirty-two participants entered phrases from a standard corpus on an iPhone, once using the software keyboard and once using Baidu's Deep Speech 2 recognizer. In English, speech ran at 153 words per minute against the keyboard's 52 — a factor of 2.93. In Mandarin, 123 against 43. Speech was also more accurate: about 20% fewer errors in English, and dramatically fewer in Mandarin.

This is good work. The sample is adequate, the corpus is standard, the effect is large, the result replicates the intuition of anyone who has dictated a text message. It is exactly the kind of study a thesis wants behind it.

And it must be granted its full force before it is questioned. Speech really is faster than thumbs. That is not a marketing claim; it is a measurement.

## 3. Where the inference goes wrong

Notice, though, what the paper is called. *On Mobile Devices*. The authors were precise about their scope. The displacement thesis is not in the paper — it is in the citation of the paper, and it gets there by three quiet substitutions.

**The baseline is thumbs.** Fifty-two words per minute is a *fast* soft-keyboard rate. It is also nothing like the rate of a competent typist at a full keyboard, where seventy to ninety is ordinary and a hundred is unremarkable. A meaningful part of the measured advantage is a fact about typing on glass with two thumbs, not a fact about speech. Move the comparison to a desk and the ratio falls from roughly three to something nearer one and a half — a real advantage, but no longer a rout, and no longer large enough to carry a claim about succession.

**The task was transcription, not composition.** Participants were shown phrases — *physics and chemistry are hard*, *have a good weekend* — and reproduced them. Both channels were transcribing a sentence that already existed, fully formed, outside the participant. This is the right design for the question the authors asked, which was about entry rate. But it deliberately holds constant the thing that dominates real writing: whether you know what you are going to say. Nobody, at their desk, is transcribing a sentence handed to them. They are making one up.

**The measure stops at the first draft.** Text entry rate is throughput to a produced string. It is not throughput to *finished text that has been integrated into the document you were working in*. Those are different quantities, and the second is the one a person actually cares about.

The study is not wrong. The inference from it is. A rigorous measurement of the wrong quantity is more misleading than a sloppy measurement of the right one, precisely because its rigor is borrowed by the claim it is used to support.

## 4. The variable that matters: formedness

If words per minute is the wrong instrument, what is the right one?

The proposal here is **formedness**: how complete the thought is before you begin producing it.

At one end sits the fully formed thought. You know the sentence. Perhaps you have written it before, or it is a stock construction, or you have been turning it over for a minute. Production is a matter of getting a known string out of your head and into the machine.

At the other end sits the unformed thought. You know roughly what you mean and you do not yet have words for it. Production and thinking are the same activity; you find out what you think by watching what comes out.

Almost all real writing is a mixture, but any given utterance sits somewhere on this line, and the position predicts which channel serves you better.

**For formed thought, typing wins — and not because it is faster.** It wins because a formed thought typed is produced *once*. You know the string; you emit the string; the string is correct. Speech, for the same thought, inserts a recognizer between your intention and the result, and the recognizer's output must now be read, verified, and repaired. Even at 95% accuracy you have added a proofreading pass to a task that did not have one. The speed comparison is beside the point: the channel with more steps loses even when each step is quick.

**For unformed thought, speech wins — and also not because it is faster.** It wins because speaking has lower activation energy for something you have not finished thinking. The keyboard demands a committed string; you cannot type an approximate word. Speech tolerates hedging, restarting, trailing off, and the half-sentence that finds its own end. And in this regime throughput is not even measurable, because most of the elapsed time is not production at all — it is thinking. The channel that lets you think out loud without stopping is the one that wins, at whatever words per minute.

Note the symmetry, which is the reason to trust the account: in neither regime is speed the operative consideration. The words-per-minute framing is wrong on both sides of the line, not just one. That is a sign the framing was never measuring the right thing.

## 5. What an all-speech world loses

The displacement thesis fails on more than formedness. Speech, as a medium, is missing things that written text requires, and a survey of the gaps is more convincing than any single objection.

**Speech underdetermines text.** This is the deepest of the problems and the least discussed. A spoken utterance simply does not contain the information a written one does. It has no punctuation, no capitalisation, no paragraph breaks, no distinction between *there*, *their* and *they're*, no way to specify *17* against *seventeen*, no way to say *i.e.* rather than *that is*. The recognizer must guess at every one of these, and it guesses well, and every guess is a place where you must look. The gap is not a limitation of current models — it is a property of the channel. Speech was never carrying that information.

**Some content is not linguistic at all.** Identifiers, symbols, file paths, mathematics, URLs, `camelCase`, hyphenation, matched brackets. These are not merely hard for a recognizer; they are outside the domain of speech. There is no spoken form of `getUserById` that is shorter or more reliable than typing it. Any writing that is dense in such content is writing speech cannot address.

**Speech is linear and irrevocable; text is random-access.** You cannot reach into the middle of a spoken sentence and change the third word. You must say the sentence again. Composition frequently wants exactly that move — the small local repair — and the keyboard grants it directly while speech makes you restart. This is a structural asymmetry, not a tooling gap.

**Repair is a worse task than production.** Once wrong text exists on screen, you are no longer composing; you are editing someone else's draft, and that draft is a corruption of something you already said correctly. Fighting the transcript is a distinctive and unpleasant kind of work — it consumes the attention you had allocated to the idea, and it is *more* effortful the closer the error is to right, because near-misses are harder to spot than obvious ones.

**Speech requires permission from the room.** You cannot dictate in a shared office, on a train, in a meeting, beside a sleeping child, or in any of the many hours where a person might otherwise be writing. The keyboard is silent and always available. This is not an edge case to be handled; for many people it disqualifies speech for the majority of their working time, and no improvement in recognition changes it.

**Speech broadcasts content, not merely activity.** Typing in a public place reveals that you are typing. Speaking reveals *what you are saying*, to everyone within earshot. The privacy asymmetry is total and it is inherent to the medium.

**Register drifts.** Spoken and written English are different languages. People say *um, so basically the thing is* and write *The issue is*. Dictated prose reads like a transcript, because it is one, and the destination usually wanted something else. Cleaning it up is another pass.

**And there is a plausible cognitive cost.** Speaking aloud engages the phonological loop — the same verbal-rehearsal machinery you use to hold a half-formed sentence in mind while you decide how to finish it. The psychology literature on articulatory suppression shows that concurrent speech reliably degrades verbal working memory. This is offered as a hypothesis rather than a finding about dictation specifically, but it is consistent with a common report: that composing complex, carefully structured prose aloud feels harder than composing it silently, in a way that mere speed cannot explain.

## 6. The dichotomy is false twice

The displacement thesis assumes speech and typing are substitutes competing for one job. They are complements addressing different conditions, and the assumption fails at two levels.

It fails **per user**. There is no contradiction in being a fast typist who dictates heavily. It is not a compromise or a transitional state. It means the person has correctly matched channel to formedness — typing the things they know how to say, speaking the things they are working out. Someone who does both well is not hedging; they are doing it right.

It fails **per utterance**. Even within a single document, written in a single sitting, the right channel changes sentence by sentence. The paragraph you have been mentally drafting on the walk home wants the keyboard. The next one, which you have not thought about at all, wants speech. Asking which input a *person* prefers is asking a question one level too coarse.

## 7. What follows for the tool

If the account above is right, the design consequences are not subtle.

**Speech is a support function.** The keyboard is the primary instrument and remains so. A dictation tool is not competing with it; it is filling in the cases the keyboard handles badly. That is a smaller claim than the marketing makes, and it is a considerably more defensible one.

**The hierarchy is: return control to the keyboard as fast as possible.** Every design decision that makes the tool more central — a mode you must exit, a panel you must dismiss, a clipboard it keeps, a window that takes focus — is friction charged against a channel that is not the main one. The tool should be reachable in one gesture and gone in the next.

**Optimising the delivery channel is mostly wasted effort.** If typing is the primary instrument and speech is the support, then elaborate insertion mechanisms — floating editors, review panels, in-place revision — are solving the wrong problem. They make the support channel more like a primary one. A single atomic insertion that returns you to the keyboard immediately is not a limitation to be engineered around; it is the correct shape.

**And the design target is not long-form.** If the strongest case for speech is unformed thought, the tool should be optimised for the short, rough, half-considered utterance — the one you would not have bothered to type. This is why interaction friction matters more than transcript length, and why a tool that takes three seconds to reach is a tool that never gets used for a five-second thought.

## 8. The honest version of the pitch

The category's claim is *stop typing*. The true claim is smaller and better.

It is this: **there are utterances you currently do not make, because typing them costs more than they are worth.** The passing observation, the note you would have to stop and open something for, the paragraph you cannot yet write but could say. Those thoughts are currently lost — not because you type slowly, but because the cost of capture exceeds the value of a small idea.

A good dictation tool does not replace your keyboard. It lowers the threshold at which a thought is worth capturing at all, and the yield is not speed. It is the thoughts you would otherwise not have kept.

---

## References

- Ruan, S., Wobbrock, J. O., Liou, K., Ng, A., & Landay, J. (2016). *Speech Is 3x Faster than Typing for English and Mandarin Text Entry on Mobile Devices.* [arXiv:1608.07323](https://arxiv.org/abs/1608.07323)
- Baddeley, A. D. — the phonological loop and articulatory suppression, from the working-memory literature.

*Companion notes: `axes-and-modes.md` on the structure of interaction design in this category; `ambient.md` on the principle that follows from treating speech as a support function.*
