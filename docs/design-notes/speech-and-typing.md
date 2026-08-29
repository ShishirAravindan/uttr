# Speech and Typing

*Against the claim that voice replaces the keyboard, and in favour of a different variable.*

---

## 1. The displacement thesis

The current generation of dictation products does not sell itself as a convenience. It sells itself as a succession.

Wispr Flow's pitch is that you should stop typing, that the keyboard is a bottleneck you have been tolerating, and that voice removes it. The surrounding category speaks the same way: *your voice is faster than your fingers*, *think it, say it, done*, *the end of typing*. The framing is not that speech is a useful additional channel. It is that speech is the successor input, and the keyboard is a legacy device we happen not to have retired.

Call this the **displacement thesis**: speech and typing compete for the same job, speech wins, and a rational user migrates.

It deserves a hearing, because there is real evidence behind it and the products built on it are good. It is also wrong in an interesting way, and how it fails tells you what these tools are actually for.

## 2. The evidence, at its strongest

In 2016 a team from Stanford, the University of Washington and Baidu published *Speech Is 3x Faster than Typing for English and Mandarin Text Entry on Mobile Devices*. Thirty-two participants entered phrases from a standard corpus on an iPhone, once with the software keyboard and once with Baidu's Deep Speech 2 recognizer. In English, speech ran at 153 words per minute against the keyboard's 52, a factor of 2.93. In Mandarin, 123 against 43. Speech was also more accurate, with roughly 20% fewer errors in English and dramatically fewer in Mandarin.

This is good work. The sample is adequate, the corpus standard, the effect large, and the result matches the intuition of anyone who has dictated a text message. It is exactly the kind of study a thesis wants behind it.

It must be granted its full force before it is questioned. Speech really is faster than thumbs, and it really was more accurate in that setting. Those are measurements, not marketing.

## 3. Where the inference goes wrong

Notice what the paper is called. *On Mobile Devices.* The authors were precise about their scope. The displacement thesis is not in the paper; it enters through the citation of the paper, by three quiet substitutions.

**The baseline is thumbs.** Fifty-two words per minute is a fast soft-keyboard rate, and it is not the rate of a competent typist at a full keyboard. How much faster a desk typist is varies enough between individuals that quoting a single figure would be inventing one, but the direction is not in doubt, and part of the measured advantage is a fact about typing on glass rather than a fact about speech.

There is a temptation here to recompute the ratio for a desk, and it should be resisted, because doing so honestly requires moving both numbers. The 153 was produced under conditions equally favourable to speech: reading out a short phrase that already existed. Change the setting and the speech figure moves too. The right conclusion is that the gap narrows substantially and that nobody in this argument has measured how much.

**The task was transcription, not composition.** Participants were shown phrases — *physics and chemistry are hard*, *have a good weekend* — and reproduced them. Both channels were transcribing a sentence that already existed, fully formed, outside the participant. That is the right design for the question the authors asked, which was about entry rate. It also holds constant the thing that dominates real writing: whether you know what you are going to say. Nobody at their desk is transcribing a sentence handed to them. They are making one up.

**The measure stops at the first draft.** Text entry rate is throughput to a produced string, not throughput to finished text integrated into the document you were working in. Those are different quantities, and the second is what a person cares about.

The study is sound. The inference from it is not. A rigorous measurement of the wrong quantity misleads more effectively than a sloppy measurement of the right one, because its rigor gets borrowed by the claim it is used to support.

## 4. The variable that matters: formedness

If words per minute is the wrong instrument, what replaces it?

The proposal here is **formedness**: how complete the thought is before you begin producing it.

At one end sits the fully formed thought. You know the sentence. Perhaps you have written it before, or it is a stock construction, or you have been turning it over for a minute. Production means getting a known string out of your head and into the machine.

At the other end sits the unformed thought. You know roughly what you mean and you do not yet have words for it. Production and thinking are the same activity; you find out what you think by watching what comes out.

Almost all real writing mixes the two, but any given utterance sits somewhere on the line, and its position predicts which channel serves better.

A caveat about what kind of proposal this is. Formedness has no measure. There is no instrument for it, no protocol, nothing a study could report, and it is offered as a better way to carve the problem rather than as a competitor to the Ruan result on its own terms. Someone entitled to demand rigour of that paper should note the asymmetry.

**For formed thought, typing wins, and not on speed.** The tempting argument is that a formed thought typed is produced once and correctly, while speech inserts a recognizer whose output must be read and repaired. That argument is too strong, and the study already refutes it: typing has an error rate too, and in that experiment it was the higher one.

The real asymmetry is not error rate but **error visibility**. When you mistype, you generally know. You hold the intended string, you produced the deviation yourself, and the result is usually not a word. Recognizer errors are silent. They tend to be well-formed words sitting in grammatical positions, so nothing about the text announces them, and finding them requires reading your own sentence as though someone else wrote it. A channel that produces fewer errors but hides them can still cost more attention than one that produces more errors and shows them. That survives the accuracy data, where the "produced once" version does not.

**For unformed thought, speech wins, and also not on speed.** Speaking has lower activation energy for a thought you have not finished. The keyboard demands a committed string, and you cannot type an approximate word. Speech tolerates hedging, restarting, trailing off, and the half-sentence that finds its own end. In this regime throughput is barely meaningful anyway, because most of the elapsed time is not production but thinking, and the channel that lets you think aloud without stopping wins at whatever words per minute.

In neither case is speed the operative consideration. That is not offered as evidence for the account, since the symmetry was available to whoever phrased both halves. It is offered as a reason to distrust the framing that made speed central.

## 5. What an all-speech world loses

Speech, as a medium, is missing things written text requires. The gaps below are not equally serious, and one modern answer dissolves several of them, so they need sorting rather than piling up.

**Speech underdetermines text.** A spoken utterance does not contain what a written one does. No punctuation, no capitalisation, no paragraph breaks, no distinction between *there*, *their* and *they're*, no way to specify *17* against *seventeen*, no way to say *i.e.* rather than *that is*. Written and spoken registers also differ: people say *um, so basically the thing is* and write *The issue is*. These are one problem in several costumes, and the problem is that the channel carries different information than the destination requires.

**Some content is not linguistic.** Identifiers, symbols, file paths, mathematics, URLs, `camelCase`, hyphenation, matched brackets. There is no spoken form of `getUserById` shorter or more reliable than typing it.

**Speech is linear; text is random-access.** You cannot reach into the middle of a spoken sentence and change the third word. You must say the sentence again. Composition frequently wants exactly that local repair, and the keyboard grants it directly.

**Repair is worse work than production.** Once wrong text exists on screen you are no longer composing but editing a corruption of something you already said correctly. This consumes the attention allocated to the idea, and it gets harder as errors get closer to right, because near-misses hide better than obvious ones.

**Speech requires permission from the room, and broadcasts content.** You cannot dictate in a shared office, on a train, in a meeting, or beside a sleeping child. Typing in a public place reveals that you are typing; speaking reveals what you are saying. These two are properly constraints of context rather than of the medium — they indict a phone call equally — but they bear on which input can be *primary*, since an input method requiring the room's consent cannot be the one you reach for by default.

### The objection that dissolves half of this

A well-informed reader will have been waiting to say: a language model between the recognizer and the insertion point fixes most of that list. Punctuation, capitalisation, homophones, register, disfluency removal, even light restructuring. This is not speculative; it is what the products named in section 1 ship, and it is most of what distinguishes them from a bare recognizer.

The objection is correct, and the defence that the gap is "a property of the channel rather than a limitation of current models" does not answer it. The reconstruction was never supposed to come from the channel. It comes from a model conditioned on context, and it works.

What survives is narrower and worth stating precisely.

Post-processing converts a transcription problem into an editing problem performed by something other than you. That trades one error class for a worse one: a recognizer error is usually a wrong word, while a model error is a plausible sentence you did not mean. Both are silent, and the second is harder to catch, because it reads correctly. The verification burden does not go away; it changes shape and arguably grows.

Linearity survives untouched. So does room permission. So does non-linguistic content, mostly, since a model can repair an identifier it half-heard but cannot recover one it never received. And for a local-first tool there is a further cost: the good models are large, so post-processing either adds latency and memory on-device or sends your transcript to a server, which forfeits the property that made the tool worth building.

The honest summary is that post-processing is a real answer to a real part of the list, that it is a different feature from transcription and should be argued for separately, and that it constitutes a fourth axis the companion note does not have. `axes-and-modes.md` claims its three axes are the joints of the problem and offers to locate competing products on them. It cannot locate this, which is the most commercially salient difference between uttr and the products it is compared to. That is a genuine hole in the map, and it should not be papered over by classifying transformation as packaging.

## 6. Complements, not substitutes

The displacement thesis assumes speech and typing compete for one job. They address different conditions, and the assumption fails at the granularity where it is usually applied.

Asking which input a *person* prefers is one level too coarse. Even within a single document written in a single sitting, the right channel changes sentence by sentence. The paragraph you drafted mentally on the walk home wants the keyboard. The next one, which you have not thought about at all, wants speech. Someone who types quickly and dictates heavily is not hedging or in transition; they have matched channel to formedness, which is the correct behaviour rather than a compromise.

## 7. What follows for the tool

If the account holds, the design consequences are not subtle.

Speech is a support function. The keyboard remains the primary instrument, and a dictation tool fills in the cases the keyboard handles badly. That is a smaller claim than the marketing makes and a considerably more defensible one.

The rule that follows is to return control to the keyboard as fast as possible. Every decision making the tool more central — a mode you must exit, a panel you must dismiss, a clipboard it keeps, a window that takes focus — charges friction against a channel that is not the main one.

Elaborate delivery mechanisms are therefore mostly wasted effort. Floating editors, review panels, in-place revision: these make the support channel more like a primary one, which is the wrong direction. A single atomic insertion that returns you to the keyboard is the right shape.

That last conclusion deserves a flag, because the companion note shows uttr arrived at single atomic insertion by inheriting it from the clipboard mechanism rather than by choosing it. An argument that ratifies an inherited default should be held to a higher standard than one that overturns it, and a reader is entitled to suspect the reasoning of running backwards from what the app already does.

Here is the place where this account indicts uttr rather than vindicating it. If the strongest case for speech is the unformed thought, then the tool should be best exactly where the user is rambling — and rambling is where a bare recognizer performs worst. Unformed speech is full of restarts, hedges, and abandoned clauses, and it transcribes into text that is accurate and unusable. A product that post-processes serves uttr's own best use case better than uttr does. The design target and the current implementation are pointing at different things, and the section above explains what taking that seriously would cost.

## 8. The honest version of the pitch

The category's claim is *stop typing*. A smaller claim is available and true.

There are utterances you currently do not make, because typing them costs more than they are worth: the passing observation, the note you would have to stop and open something for, the paragraph you cannot yet write but could say. Those thoughts are lost today, not because you type slowly but because the cost of capture exceeds the value of a small idea.

That is a claim about a threshold rather than about a race. It suggests measuring a dictation tool by how often it gets reached for rather than by how fast it runs — which is a harder thing to put on a landing page, and a better description of what the good ones are actually doing.

---

## References

- Ruan, S., Wobbrock, J. O., Liou, K., Ng, A., & Landay, J. (2016). *Speech Is 3x Faster than Typing for English and Mandarin Text Entry on Mobile Devices.* [arXiv:1608.07323](https://arxiv.org/abs/1608.07323)

*Companion notes: `axes-and-modes.md` on the structure of interaction design in this category, including the axis section 5 argues it is missing; `ambient.md` on what follows from treating speech as a support function.*
