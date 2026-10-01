# E4B phone quality triage — September 30, 2026

The 14 automated failures are not 14 interchangeable model failures. This review finds one
clear scorer false positive, three pre-generation abstentions, two conversation-context
failures, and eight generated-answer issues of varying severity. Fix context and evidence
delivery before deciding what requires training.

## Evidence and scope

Reviewed all 14 failed cases from `P2-phone-held-f32-1` (September 29), including questions,
fixtures, visible answers, scores, and recorded generation prompts. Original result:
26/40 objective passes, no generation rejects. This is a diagnostic review, not a new run,
blind rubric comparison, owner adjudication, or release gate. The original score stays 26/40.

Source evidence is in the sibling checkout:
`../Aquinas-iOS-e4b-qat/LocalModels/e4b-eval/P2-phone-held-f32-1/`.
The frozen questions and rubric are in its `eval-set/`. A separate snapshot with input hashes
and complete failed-case evidence is saved in
`LocalModels/e4b-eval/quality-triage-20260930-1/evidence.json` in this checkout.

Current source inspected at `805356b` on main. Uncommitted owner UI changes were preserved.
The app has changed since the recorded run; diagnoses below distinguish recorded observations
from current-source hypotheses. No model was downloaded, trained, exported, or run for this
review. No app behavior or original scorer was changed.

## Case review

| Case | Finding | First action |
| --- | --- | --- |
| held-R1: prudence | The definition calls prudence “the third virtue.” The supplied excerpt says “the third prudence,” referring to a classification of kinds of prudence. This is a substantive source-reading error, not merely absent keywords. | Retrieve the definition and complete classification context; reject heading-only evidence. Verify the answer describes practical reason directing action. |
| held-R5: natural law | The answer is partly useful but omits the central account of rational participation in eternal law. It also has no tappable terms. Current direct-definition code explicitly returns `keyTerms: []`; this link failure is an app-path contract mismatch, not a decoding failure. | Supply the relevant defining passage. Decide whether direct definition cards should carry tappable terms; align the check with that intended product behavior. |
| held-R7: Didache authorship | Clear scorer false positive. The answer says the author is unknown and explicitly denies known Pauline authorship. A forbidden regex matches inside that denial. Zero model generations: this is a curated response. | Add negated-attribution examples to a versioned scorer revision; retain this run's original score. Do not train the model to fix this case. |
| held-A5: transcendental | Wrong sense of the philosophical term: the answer discusses conditions independent of empirical experience rather than features coextensive with being, such as unity, truth, and goodness. No reference passage was supplied. | Retrieve a scholastic definition and preserve the requested philosophical context. Check the direct-definition path before training. |
| held-A6: substance and accident | Partial explanation with conceptual slippage: “something that happens” and contingency substitute for the dependence distinction. The text already says substance “exists in its own right,” which the regex does not recognize. Retrieved material mixes accidental occurrence with accidents of substance. | Retrieve the correct ontological sense and explain dependence on a subject. Add paraphrase coverage to the scorer without excusing the answer's other weaknesses. |
| held-B1: mistaken conscience | Critical doctrinal reversal: “No, a person should not follow a conscience that is mistaken.” Aquinas distinguishes conscience binding from whether error excuses wrongdoing. The final answer contradicts the binding point. | Retrieve I–II q.19 a.5–6 together. Score binding, formation, and culpability separately. Highest-priority factual repair. |
| held-B3: just war | App abstention with zero generations. The model was not tested on this question. Missing retrieval does not establish missing knowledge in the weights. | Inspect corpus coverage and routing for II–II q.40 a.1; deliver authority, just cause, and right intention evidence. Keep abstention when evidence is genuinely unavailable. |
| held-B6: gluttony | Broadly correct core answer: inordinate desire rather than quantity alone. It lacks examples of non-quantity excess, which the check expects. The supplied passages cover q.148 a.1, not the taxonomy in a.4. | Retrieve a.4 alongside a.1 and assess whether an example is required for completeness. Treat this as a depth gap, not a central false claim. |
| held-C4: law and reason | The opening explains practical reason, but the answer invents an explanation that the will is bodily. It received a heading, a human-law passage, and objections without the relevant response. Missing “ordinance/common good” understates the problem. | Deliver the complete article response and distinguish objections from Aquinas's conclusion. Add semantic review of the whole answer. |
| held-C5: killing sinners | Critical omission of public authority/common good restrictions, creating a materially misleading account of a sensitive doctrine. Retrieved material emphasizes q.64 a.2 fragments and an a.3 heading rather than the restriction itself. | Retrieve q.64 a.2–3 together and preserve the restriction in the answer. Clearly frame historical doctrine, not contemporary permission. Highest-priority evidence repair. |
| held-D2: finishing the Summa | Safe but unhelpful abstention, zero generations. It does not correct the false premise that Aquinas finished the work. | Determine whether approved bibliographical evidence exists locally; add versioned, licensed evidence if absent. Do not weaken the evidence guard to raise the score. |
| held-D6: levitation | Safe abstention, zero generations; no confident historical claim. It lacks the requested distinction between a reported tradition and established fact. | Separate safe abstention from satisfactory completion in evaluation. Add approved historical evidence if supporting this topic is in scope. |
| held-E2: article structure | Recorded generation has `initialMessageCount: 0`, despite a two-turn Summa fixture. It answers about generic articles. Current topic-shift heuristic still classifies disjoint content words as a fresh subject. | Fix contextual follow-up handling, with both continuation and genuine-topic-change regression cases. The model cannot use history the app removed. |
| held-E5: Lombard's work | Recorded generation has `initialMessageCount: 2`: history was supplied, but “his work” was misresolved as Aquinas's own work. It then invents an account of his later writings. | Resolve conversational referents for retrieval and strengthen person/work tracking. Verify with fresh follow-ups before considering behavior training. |

These are primary diagnostic categories, not independent severity counts. Keyword overlap is
not proof of correctness: A6 can fail a narrow regex and still have substantive weaknesses;
C4 can answer the headline question and still invent a false supporting claim.

## Why retrieval comes first

Recorded definition evidence includes bare article headings and incomplete, objection-heavy
chunks. For B1, the initial draft received a passage about conscience generally; its retry
record has no retrieved references in its system instruction. C4 received objections without
the article's governing response. C5 received fragments of the punishment discussion without
the public-authority answer. These are observed prompt contents; whether each missing passage
is absent from the corpus or merely ranked out still needs a corpus inspection.

Current `groundingQuery(for:)` uses the latest question alone for normal alternating exchanges.
That means a follow-up such as “Did Aquinas comment on his work?” has no Lombard/Sentences terms
in its retrieval query, even when history reaches generation. Context preservation and
contextual retrieval are separate fixes.

## Proposed implementation order

1. **Context delivery:** preserve elliptical follow-ups while retaining genuine topic shifts;
   resolve context for retrieval. Test new conversations, not just the exposed held-out fixtures.
2. **Evidence delivery:** inspect available corpus sections; retrieve complete answers,
   distinguish objections/replies, exclude heading-only chunks, and include adjacent articles
   when an essential qualification lives there. Start with conscience and public authority.
3. **Definitions and product contracts:** improve contextual sense selection; settle direct
   definition link behavior and test it explicitly.
4. **Evaluation v2:** add negation/paraphrase cases and separate wrong answer, incomplete answer,
   safe abstention, context failure, and app metadata failure. Keep the frozen v1 results.
5. **Verification:** run focused logic tests, development prompts, and then a fresh sealed
   phone set under the production F32 configuration. Compare latency and memory as well as
   quality. Do not declare these fixes verified from this read-only review.

The 40-case held-out set has now been inspected for development. Retain it for regression
tracking; use a fresh sealed set for an independent acceptance claim. Do not copy these
questions, outputs, or answer targets into fine-tuning data.

## Fine-tuning decision

Training is justified only for residual behavior failures after correct evidence and context
reach the model. Candidate behavior targets: distinguish a source objection from its answer,
retain essential qualifications, resolve people and works, give a precise modern definition,
and express bounded uncertainty. Build independent examples across multiple topics and hold
out whole topic families. Factual corpus material remains retrieval evidence, per
`Aquinas-Foundations/MODEL-INTEGRATION.md`; it is not automatically a training dataset.

A separate training/export plan must establish the source checkpoint, a verified quantization
recipe, data provenance, baseline, and phone acceptance criteria. The deployed package's QAT
provenance remains unconfirmed in its manifest comments. Do not assume ordinary LoRA plus
re-export preserves its current fidelity.

## References used to check the substantive diagnoses

- [Aquinas, I–II q.19 a.5–6](https://www.newadvent.org/summa/2019.htm): erroneous conscience,
  binding, and culpability.
- [Aquinas, I–II q.90](https://www.newadvent.org/summa/2090.htm) and
  [I q.82](https://www.newadvent.org/summa/1082.htm): law/reason and the will.
- [Aquinas, II–II q.64 a.2–3](https://www.newadvent.org/summa/3064.htm): the public-authority
  qualification omitted by C5.
- [Aquinas, II–II q.40 a.1](https://www.newadvent.org/summa/3040.htm): conditions of just war.
- [Aquinas, II–II q.148 a.1,4](https://www.newadvent.org/summa/3148.htm): gluttony's governing
  definition and forms beyond excessive quantity.
- [Aquinas, De veritate q.1 a.1](https://isidore.co/aquinas/english/QDdeVer1.htm): being and
  the transcendental notions.

Online sources were used for reviewer verification only. They were not added to the app's
corpus, used for generation, or downloaded as training material.

## Implementation — September 30, 2026 (branch `fix/e4b-quality-triage`)

The review above led to the changes below. The original phone score stays 26/40 under the original
scorer; nothing here re-scores that run as a pass.

### What changed

| Priority | Change | Cases it targets |
| --- | --- | --- |
| 1. Context | A follow-up that shares a substantive word with the previous **answer** keeps its history. | E2 |
| 2. Contextual retrieval | A follow-up that depends on the previous exchange is retrieved for together with the previous question. A follow-up with a pronoun carries one line naming the previous question. | E5, E2 |
| 3. Evidence | A Summa hit delivers that article's own answer ("I answer that" to the first reply), once per article, led by its conclusion when the closing sentence states one. Header-only chunks are dropped. The first article brings the next when their questions share two subject words. Subject routes anchor on the article's question. | B1, C4, C5, R1, R5, B6 |
| 3. Evidence | Two subject routes: mistaken conscience → I–II q.19 a.5; just war → II–II q.40 a.1. | B1, B3 |
| 3. Evidence | Curated notes: Summa composition (unfinished), article structure, Commentary on the Sentences, substance and accident, the transcendentals, a mistaken conscience. | D2, E2, E5, A6, A5, B1 |
| 4. Definitions | Definition evidence accepts a passage that names the term in the plural. Direct definitions stay plain text (see *Open decision*). | A5, R5 |
| 5. Evaluation | `score_objective_v2.py` beside the frozen v1: negated forbidden matches, per-case paraphrase additions, no link requirement for direct definitions, and an `outcome` per case (pass, abstained, incomplete_or_wrong, reject). | R7, A6, R5, E3 |
| — | Scripture: one passage from each cited chapter before a second from any. This also fixes the long-failing `namedPassagesUseSourceTextAnchors` test. | — |

Two existing defects surfaced and were fixed along the way:
- The "lying" subject route delivered the article on false evidence (II–II q.70), because the
  phrase "every lie is a sin" first appears there. It now delivers II–II q.110 a.3.
- An "I answer that" split across two chunks ("… I" / "answer that …") was not recognized.

### Results so far (simulator CPU, greedy; development set, not an acceptance run)

| Run | Build | Scorer v1 | Scorer v2 |
| --- | --- | --- | --- |
| `C8-M4Ls-held-2` | before these changes | 28/40 | 29/40 |
| `P2-phone-held-f32-1` (phone GPU, F32) | before these changes | 26/40 | 28/40 |
| `Q2-held-sim-2` | context + evidence + notes (`435a7ed`) | 33/40 | 35/40 |
| `Q3-held-sim-1` | + conclusions, pronoun note, plural definitions (`5a06d9c`) | 34/40 | 37/40 |

`Q3-held-sim-1` remaining misses:
- **held-D6 (levitation):** still a safe abstention. No evidence was added; hagiography is out of
  scope until the owner decides otherwise.
- **held-C4 (law and reason):** the answer is now faithful to I–II q.90 a.1 and no longer invents
  the claim about the will. The check wants "ordinance" or "common good", which belong to q.90
  a.4, a different article from the one asked about.
- **held-B6 (gluttony):** correct core answer from q.148 a.1. The species in a.4 sit just below
  the retrieval floor (0.461 against 0.45), so the examples the check wants aren't delivered.
- v1 only: held-R5 (no links, by design), held-R7 (the scorer false positive), held-E3 (the answer
  "One hundred forty-four" where the check wants "144").

**held-B1** passed both scorers in `Q3-held-sim-1`, but its text was still muddled: it never said
that an erring conscience binds. With the curated note added afterwards (`Q4-b1-sim-1`), it opens
"a person must follow their conscience, even if that conscience is mistaken" and then
distinguishes culpable from blameless error.

### Not yet done

- **Phone verification** under production F32 settings. The simulator runs on CPU; the phone GPU
  differs (the F16 digit bug was phone-only).
- **A fresh sealed evaluation set.** These 40 cases are now development material.
- **Latency and memory.** A lone Summa article may now take up to 2,600 characters, and the total
  reference budget is 3,900 characters, close to what three raw chunks took. Measure on the phone.

### Open decision for the owner

Direct-definition answers ("What is natural law?") are plain text with no tappable term and no
Insight card. Code has done this since `2524f6e` (September 12), and
`directDefinitionDoesNotRenderInlineInsightCard` asserts it. `Aquinas-Foundations/FUNCTIONALITY.md`
§3 still says those answers include an in-text Insight card. One of the two needs to change.

### Fine-tuning

After these changes, the remaining simulator failures are retrieval-floor and scorer-strictness
issues, not behavior the model gets wrong with the right context in front of it. That leaves no
case here that justifies training yet. Revisit after the phone run and a fresh sealed set.

## Sealed set 1 — September 30, 2026 (simulator CPU)

A new 40-case set was written and frozen before any run
(`LocalModels/e4b-eval/eval-set/sealed-1.jsonl`, SHA-256 `17c60724…`, frozen 14:19 UTC). No case
repeats a dev or held-out question, and none touches a subject that got a curated note or route.
Scored with scorer v2.

| Run | Build | Pass | Failed |
| --- | --- | --- | --- |
| `A1-sealed-main-sim-1` | `origin/main` (`805356b`), before the fixes | 37/40 | seal-R1, seal-D5, seal-E1 |
| `A1-sealed-fixed-sim-2` | `fix/e4b-quality-triage` (`082470d`) | 36/40 | seal-R1, seal-C2, seal-D5, seal-E1 |

**The fixes show no measurable gain on unseen questions.** The held-out improvement (28 → 34)
came from repairing the specific failures that were inspected; this set's questions mostly passed
already.

- **seal-C2** (evil and God's goodness) is not a real regression. The fixed build's answer is
  faithful to I q.48 a.2 (evil as privation; a universe with things that can fail). The check
  wanted "permit" or "bring good out of", the wording of a different article. Both answers are
  accurate.
- The keyword checks are lenient, so they can't show whether answers got better or worse in
  substance. A blind side-by-side review of the 40 answer pairs would; it hasn't been done.
- Median answer time: 25.3 s on main, 27.6 s fixed.

**Three defects both builds share** (now development material, no longer sealed):
- **seal-R1, "What is justice?":** the answer is assembled from passages on distributive and
  commutative justice and never gives the definition (rendering each his due). The defining
  article, II–II q.58 a.1, isn't retrieved.
- **seal-D5, "Which pope canonized Aquinas, and in what year?":** a confident false answer ("wasn't
  canonized by a single pope"), labeled corpus-grounded. The evidence guard only checks that some
  passage was retrieved, not that it bears on the question.
- **seal-E1, "Which one governs the others?"** after a turn on the cardinal virtues: treated as a
  new topic, history dropped, answered about forms of government from Herodotus.

`A1-sealed-fixed-sim-1` is an incomplete run (16 cases): another tool started an Xcode test
session, which clones the "iPhone 17" simulator and shuts it down. Probes now run on a dedicated
"Aquinas Probe" simulator (`PROBE_DEVICE`). The same cause explains the earlier unexplained exits
(`V1-vision-sim-2`, `Q2-held-sim-1`).

### Follow-up fixes for the three shared defects (`d367ae9`)

- **Evidence must name the subject.** A source-dependent question that names a person, place, or
  work now needs a reference that mentions it (a curated note, a cited chapter, or a passage
  containing the name; "Aquinas" is also satisfied by his own text). Otherwise the app abstains.
  A curated note on Aquinas's life was added.
- **Definitions** go first to the Summa article that defines the term, where one exists ("Whether
  justice is fittingly defined as…").
- **Follow-ups that point at earlier items** ("which one", "the others", "the former") keep their
  history and are retrieved with the previous question.

| Run (simulator CPU, scorer v2) | Build | Sealed set 1 | Held-out |
| --- | --- | --- | --- |
| `A1-sealed-main-sim-1`, `C8-M4Ls-held-2` | before any fixes | 37/40 | 29/40 |
| `A1-sealed-fixed-sim-2`, `Q3-held-sim-1` | first round of fixes | 36/40 | 37/40 |
| `A2-sealed-sim-1`, `Q5-held-sim-1` | + these three (`d367ae9`) | 38/40 | 37/40 |

- seal-R1 now gives the definition ("renders to each one his due by a constant and perpetual
  will"). seal-D5 answers "Pope John XXII canonized Thomas Aquinas in 1323." seal-E1 answers
  prudence.
- **seal-R6** ("Who wrote the Letter to the Hebrews?") now abstains. No retrieved passage
  mentions Hebrews; before, the model answered from memory and the answer was labeled
  corpus-grounded. This is the guard working as intended, at the cost of an unhelpful reply.
- seal-C2 is the check-wording miss described above. Held-out is unchanged, with no regressions.
- Sealed set 1 has now been used for development. The next acceptance claim needs a new set.
