# Case study: a bigger model in the same pocket — Ternary Bonsai 2 vs Gemma 4 E4B

October 15–19, 2026. Angrove 1.0 shipped with Gemma 4 E4B. This study asks whether PrismML's
Ternary Bonsai 2 models (9B and 4B, weights compressed to three values) are a better on-device
model for Angrove after launch.

## Summary

- **Update (October 20):** retrieval is the real upgrade. With an opt-in web search, model-written
  queries and a tiny reranker, E4B rose from 31 to 37/40 on the hard set and Bonsai 4B from 30
  to 35, at nearly unchanged answer time. See "Would web search help?".

- **No, not as a drop-in replacement.** On the base iPhone 17, Bonsai 9B was less accurate,
  slower and hotter than E4B. Bonsai 4B was fast and cool but slightly less accurate.
- **The cause is the compression, not the model family.** The same 9B model at near-full
  precision (Qwen3.5-9B, 6-bit) scored **37/40** on our hard set. The ternary Bonsai version of
  it scored **29/40**, below E4B's 31–32. The losses are almost all confidently wrong facts:
  dates, names, attributions.
- **Prompting does not fix it.** A prompt written for Bonsai scored the same 29/40 with the same
  errors.
- **What would change the answer:** retrieval that reliably supplies the right passage (so the
  model reasons over sources instead of recalling facts), a less aggressive compression of the
  9B, or a phone with more memory.

## The question

PrismML's pitch: a 9B model in about 2.4 GB, smaller than our 4B-class E4B (about 3.6 GB), with
benchmark scores close to the uncompressed model. If that held for Angrove's questions (Aquinas,
Church history, philosophy, multi-turn reasoning), we would get a smarter model at no memory cost.

## What we built

- **A second runtime behind one protocol.** `AngroveTextRuntime` sits between the app's model
  layer (`LiteRTAngroveModel`) and the engines: LiteRT-LM for Gemma, and a new
  `LlamaAngroveRuntime` on PrismML's llama.cpp fork for any GGUF model. Bonsai stays behind a
  Debug-only flag; Release always uses E4B.
- **An isolated phone test app.** A Release build with its own bundle ID and App Group
  (`…ModelProbe`), so experiments never touch the production app or its data. It records thermal
  state, memory, battery and per-call engine timing for each question.
- **A harder question set.** The standard 40-question set had saturated: all three models scored
  34–39. `hard-1` (40 questions) adds precise Thomistic distinctions, rankings, false premises,
  exact historical facts and 10 multi-turn cases. Prompt tuning used only the separate practice
  set, never `hard-1`. The sealed acceptance set was never opened.

## Results

### Standard set (40 questions), Mac

| Model | Held-out | Sealed-1 | Total |
| --- | --- | --- | --- |
| Gemma 4 E4B | 36 | 36 | 72/80 |
| Bonsai 9B | 37 | 39 | 76/80 |
| Bonsai 4B | 35 | 35 | 70/80 |

Bonsai 9B's lead was mostly the scorer: reading the answers showed regex passes covering
invented details and one lost multi-turn context. This set could not separate the models.

### Speed experiments (Mac, held-out)

A shorter Bonsai prompt cut answer time by about 42–46% (9B: 11.6 s → 6.7 s median) but lost
about two answers' worth of quality. Prism's recommended sampling settings changed quality by one
case either way and did not change speed.

### Phone matrix (base iPhone 17, Release build, held-out 40)

| | E4B | Bonsai 9B (short prompt) | Bonsai 4B (short prompt) |
| --- | --- | --- | --- |
| Score | 35/40 | 36/40 (one false pass) | 34/40 |
| Median / p90 answer | 22.6 / 37.8 s | 19.8 / 33.6 s | 12.7 / 17.9 s |
| Cold load | 9.0 s | 3.1 s | 1.6 s |
| Reached "serious" heat | 659 s | 535 s | never |
| System memory evictions | 0 | 2 | 0 |

### Hard set (40 questions)

| Model | Mac | Phone | Mac median |
| --- | --- | --- | --- |
| Gemma 4 E4B | 31 | 32 | 8.5 s |
| Bonsai 9B, standard prompt | 29 (three identical runs) | 29 | 10.8 s |
| Bonsai 9B, Bonsai-tuned prompt | 29 | — | 10.4 s |
| Bonsai 4B | 30 | — | 7.9 s |
| **Qwen3.5-9B, 6-bit (control)** | **37** | — | 15.7 s |

On the practice set, the same pair scored Qwen3.5-9B 35/40 and Bonsai 9B 30/40.

On the phone, the full-prompt 9B was also slower (30.3 s median vs E4B's 22.9 s), hit "serious"
heat in 7 minutes vs 12, and caused one memory eviction (E4B: none).

## Why Bonsai loses facts

Bonsai 9B's hard-set misses are confident factual errors, not reasoning failures:

| Question | Bonsai 9B said | Correct |
| --- | --- | --- |
| Which Way argues from things lacking intelligence acting for an end? | "The third way" | Fifth Way |
| Did Augustine write the Athanasian Creed? | "Composed by Athanasius … around 381" | Author unknown |
| (After "Nicaea was 325") "No, it was 451" | "451 was the First Council of Constantinople" | 451 is Chalcedon |
| Can reason prove the world had a beginning? | "Yes" | No; Aquinas holds it by faith |
| Practice set: did Aquinas and Bonaventure die the same year? | "Bonaventure died in 1273" | Both 1274 |

It still beat E4B on some conceptual questions. E4B called the Fourth Way an argument from
design; Bonsai correctly said degrees of perfection.

**Control test.** Bonsai 9B is Qwen3.5-9B with its weights compressed to three values. Running
Qwen3.5-9B at 6-bit (effectively lossless) through the identical app pipeline, prompt and greedy
decoding fixes most of those errors: Augustine/Creed (anonymous), Boethius (imprisoned, 524),
Nicaea/Chalcedon, the world's beginning (not provable), and mortal sin destroying charity.
Score: 37/40 vs Bonsai's 29. So the base model knows these facts, and ternary compression loses
them. That fits the usual pattern: rare facts are stored in fine weight detail, and they go first
when weights are compressed. Reasoning and common knowledge, which benchmarks emphasize, survive
better.

Caveats:
- The 6-bit Qwen still makes some confident errors. It calls Aristotle "the Commentator"
  (Averroes), invents a source for the "straw" remark, says Aquinas attended Lyon (he died on
  the way) and still says "third way". Its 37 includes a few scorer passes on wrong answers, so
  its real lead is smaller than 8 questions but still clear.
- It needs about 7.5 GB and ran about 45% slower than Bonsai 9B on the Mac. It is a diagnostic
  control, not a phone candidate.
- Not every Bonsai error is compression: on the practice set the 6-bit Qwen also gets the
  Bonaventure date wrong (and passes the regex anyway).
- One greedy run per configuration. Bonsai's three identical runs show the pipeline is
  deterministic, but 1–2 question differences are within question-set noise.

## How much compression is too much?

The same Qwen3.5-9B at several compression levels, on the hard set (Mac, identical pipeline):

| Version | File size | Hard set |
| --- | --- | --- |
| Bonsai 9B (ternary, ~1.6 bits) | 2.4 GB | 29/40 |
| Gemma 4 E4B (reference) | ~3.6 GB | 31/40 |
| Qwen3.5-9B ~2.5-bit (UD-Q2_K_XL) | 4.1 GB | 33/40 |
| **Qwen3.5-9B 3-bit (Q3_K_M)** | **4.7 GB** | **37/40** |
| Qwen3.5-9B 4-bit (Q4_K_M) | 5.7 GB | 37/40 |
| Qwen3.5-9B 6-bit (Q6_K) | 7.5 GB | 37/40 |

Quality is fully back at 3 bits, and even 2.5 bits beats E4B. The cost is size and speed:
about 1.3–1.9× E4B's file size and about 1.8× its Mac answer time. **On the base iPhone 17 (8 GB) neither fits:** both the 3-bit and 2.5-bit files were killed by
the system for memory (about 6.2–6.6 GB wired) before answering a question. A 12 GB Pro-class
iPhone, partial CPU offload, or a smaller context are the untested ways forward.

The 4B tells a different story. Qwen3.5-4B (Bonsai 4B's base) scored 34/40 at 4-bit (2.7 GB,
9.1 s on the Mac) and 33/40 at 6-bit. Reading the answers puts it at roughly E4B's level: it
fixes some E4B errors but makes its own confident ones (451 as "Ephesus", the Creed "by
Athanasius"). More bits did not help, so the 4B's limit is the model's size, not its compression.

## What if retrieval were perfect?

We gave each model a hand-written correct passage for every hard-set question (an upper bound
for retrieval; the passages contain the checked facts, so this is close to a reading test):

| Model | Size | Normal → correct passage supplied | Mac median |
| --- | --- | --- | --- |
| Gemma 4 E4B | ~3.6 GB | 31 → 40 | 7.1 s |
| Qwen3.5-4B 4-bit | 2.7 GB | 34 → 40 | 7.8 s |
| Bonsai 9B | 2.4 GB | 29 → 39 | 9.4 s |
| Bonsai 4B | 1.15 GB | 30 → 39 | 6.7 s |

With the right source in hand, every model gets nearly all the facts right, so for factual
accuracy, retrieval matters far more than model size. Differences remain in conversation
handling: Bonsai 4B lost the context of one follow-up entirely, and Bonsai 9B still misdated
451 despite the passage. No model admitted the deliberately wrong earlier answer in the
revision case; it just restated the correct view.

## Would web search help?

A Wikipedia stand-in for an opt-in web search (naive query and passage picking, results
appended to normal retrieval, identical text for every model):

| Model | Normal | + Wikipedia | Correct passage |
| --- | --- | --- | --- |
| Gemma 4 E4B | 31 | 32 | 40 |
| Bonsai 4B | 30 | 32 | 39 |
| Qwen3.5-4B 4-bit | 34 | 37 | 40 |

Only a small gain, because simple search often fetched the wrong pages (Nietzsche for a
Boethius question, Ted Bundy for "it was 451"). It can also hurt: with web text present the
app stopped declining one question, and E4B then gave a confident wrong answer. Web search is
only worth it with good query rewriting and relevance ranking, the same skills good
retrieval needs.

A second version had E4B write focused search queries (about 1.5 s each) and ranked paragraphs
by meaning with the app's MiniLM model. That found the right Wikipedia articles far more often,
but still picked the wrong paragraphs within them, so scores rose only slightly (E4B 33, Bonsai
4B 32, Qwen3.5-4B 36). Passage ranking, not search, is now the weak link.

Adding a reranker, a small model that reads the question and each paragraph together, fixed
that:

| Model | Normal | Web + tiny reranker (22M) | Web + large reranker (568M) | Correct passage |
| --- | --- | --- | --- | --- |
| Gemma 4 E4B | 31 | **37** | 38 | 40 |
| Bonsai 4B (1.15 GB) | 30 | **35** | 35 | 39 |
| Qwen3.5-4B 4-bit | 34 | **37** | 38 | 40 |

The tiny reranker took about 0.6 s per question on the Mac and captured almost all of the gain.
E4B with it matches the 3-bit 9B that doesn't fit the phone, and Bonsai 4B with it beats E4B
without it. Reading the answers confirms the gains are real (Chalcedon, the Fifth Way,
transubstantiation, Boethius under Theodoric); the remaining misses are mostly scorer
strictness plus "the Commentator".

## Other findings

- **Retrieval misses natural questions.** The MiniLM retriever finds Summa articles by their
  "Whether …?" heading wording, not by natural questions. Example: "Which theological virtue is
  greatest?" doesn't retrieve ST I-II q.66 a.6, even though it's in the corpus. The app's
  evidence gate also declines some answerable questions ("I don't have a reliable passage…").
  This affects every model.
- **Subjectless follow-ups** ("Which is greatest?") lost their topic in retrieval. An opt-in
  routing fix (`FollowUpRouting.evaluativeAware`) restores the context; it is not on by default.
- **Bonsai trusts passages that are on topic but incomplete.** E4B, given the same passages,
  falls back on what it knows.
- **Test hygiene.** Mac test runs share the app's bundle ID. Another agent relaunching the Mac
  app quits the test host mid-run, and quitting while Bonsai is generating crashes it, because
  exit cleanup frees the model under a running generation. Mac-only, behind the flag; fix
  before any Bonsai ship.

## Decision and post-launch paths

E4B stays the model. Bonsai stays behind its Debug flag. Paths worth revisiting, best first:

1. **Retrieval quality** (the oracle test shows this is the biggest lever), independent of the model: index question-form aliases for Summa
   articles or rewrite queries into "Whether …" form, measured on the gold-passage fixtures.
   This also makes a reasoning-strong, fact-weak model like Bonsai more viable.
2. **A less aggressive 9B.** 3-bit Qwen3.5-9B (4.7 GB) matches the 6-bit control on the Mac.
   It does not fit the 8 GB base iPhone 17 (killed for memory); test on a 12 GB Pro-class phone.
3. **A 4B light tier** for devices that can't hold E4B: Bonsai 4B (1.15 GB, cool) or Qwen3.5-4B
   at 4-bit (2.7 GB, about E4B quality). Neither is an upgrade over E4B on capable phones.
4. **Thinking mode**, untested here, for reasoning-heavy questions where latency is acceptable.

## Evidence

All runs are immutable folders in `~/Developer/Angrove-Eval/runs/`, scored with
`score_objective_v2.py`; details in `Angrove-Eval/RESULTS.md`.

- Standard set: `B9-MAC-*`, `B4-MAC-*`, `ME4B-GPU-*`; prompt/sampler: `B*-MAC-prism-*`,
  `B*-MAC-compact-*`; follow-ups: `FU-*`.
- Phone: `PH-{E4B,B9C,B4C}-heldout-1`, `PQ-{E4B,B9}-standard-hard-1`.
- Hard set: `HM-E4B-standard-1`, `HM-B9-standard-1`, `HM-B9-tuned-2`, `HM-B4-standard-3`;
  control `QC-B9-standard-hard-1`, `QC-Q6-standard-hard-1`. Question set
  `eval-set/hard-1.jsonl` (builder `build_hard_set_1.py`).
- Control model: unsloth `Qwen3.5-9B-Q6_K.gguf`, SHA-256 `91898433…6c59` (matches the
  published hash), base model of Bonsai 9B per its model card.
- Engineering logs: [`Bonsai-9B-Handoff.md`](Engineering-Log/Bonsai-9B-Handoff.md),
  [`Bonsai-Claude-Handoff.md`](Engineering-Log/Bonsai-Claude-Handoff.md),
  [`Bonsai-Optimization-Plan.md`](Engineering-Log/Bonsai-Optimization-Plan.md).
