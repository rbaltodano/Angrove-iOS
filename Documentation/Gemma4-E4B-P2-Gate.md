# Gemma 4 E4B — P2 promotion gate (draft, not yet frozen)

> Status: **draft**, 2026-09-28. It becomes binding only when the owner (or the delegated senior
> developer) marks it frozen in a commit, **before** any P2 run. C9 stays `failed`; P2 is a new
> gate, not a rerun of C9. Why a new gate: C9 applied a 4 s answer budget to a cold trial whose
> model load alone takes 8–15 s, and the current model (B0) fails the same budget. Evidence is in
> `Gemma4-E4B-Post-C9-Diagnostics.md`.

## Principle

E4B replaces B0 only if daily use on the base iPhone 17 is **no worse than B0** on latency and
system impact, and **better** on quality. Limits are relative to B0, measured the same day, on
the same phone, with the same build.

## Preconditions

1. The phone's production app runs a build that contains `a4fd7c0` (the bounded-memory SHA
   fix). Resolve the owner's 2026-09-28 memory report first (see the diagnostics doc).
2. Both arms use **Release** builds under the disposable bundle ID. Release skips the DEBUG
   model hash (the bundled seed isn't hashed in Release; receipts apply only to downloaded
   models). A DEBUG build is used only for the timing harness, and is labelled as such.
3. Back up production data first. Never use `--remove-existing-content` on production.

## Measurements (5 trials each unless stated; report every sample, the median, and the max)

| # | Metric | E4B limit |
| --- | --- | --- |
| M1 | Cached load | ≤ B0 median + 2 s, and ≤ 10 s max |
| M2 | Warm answer, short prompt (model already loaded; request → answer complete) | ≤ B0 median × 1.10 |
| M3 | Warm answer, justice-and-mercy prompt (≤180 words) | ≤ B0 median × 1.10, and ≤ 60 s max |
| M4 | Cold load after install (cache cleared), 1 trial each | ≤ 20 s (informational vs B0) |
| M5 | 20 consecutive turns: turn-20 ÷ turn-2 latency | ≤ 1.5× |
| M6 | Peak memory: jetsam resident pages (primary) and `phys_footprint` | ≤ B0 |
| M7 | **Background audio survives**: Music playing, 5 questions | Audio never stops; no JetsamEvent names another app during the run |
| M8 | Thermal state | Never `critical` |
| M9 | 5 real OS background/foreground cycles during generation, then a request | All recover; the next request succeeds |
| M10 | 1 memory warning during generation, then a request | Next request succeeds |
| M11 | Phone-GPU quality: the frozen 40-case held-out set | No worse than C8's simulator result for E4B (critical ≤ 1; mean accuracy ≥ 3.6) |

Any jetsam of the Aquinas process, or any failed recovery, fails P2 outright.

## Run order

B0 and E4B alternate for M1–M3 and M5, to limit thermal and ordering bias. M7 runs for both
arms with the same track. M11 runs last (it takes about an hour).

## On result

- **Pass:** finish C10: rollback check, PR from `feature/gemma4-e4b-qat`, merge with the owner's
  OK, and swap main's gitignored seed.
- **Fail on M6/M7 only:** try one new configuration (2,048-token KV cache, or a shorter idle
  unload) as a new candidate with its own frozen P2 run.
- **Fail on M11 or latency:** stay on B0; record it, and move the effort to prompt-size
  reduction, which helps both models.
