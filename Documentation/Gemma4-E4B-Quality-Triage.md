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
