# Request-centric attention — implementation journal

Append-only. One entry per unit, written **before** the next unit starts.
Manifest: [`request-centric-attention-implementation-plan.md`](request-centric-attention-implementation-plan.md).

Entry format: `UNIT` · `STATUS` · `WHAT` · `FILES` · `TESTS` (commands + real results) · `FINDINGS` ·
`DECISIONS` · `REMAINING`.

---

## UNIT 01 — Product contract · ACCEPTED (2026-09-18)

**WHAT.** Wrote the durable product contract and wired it into the documentation index and glossary, so the
attention rules stop being re-derived from plan documents.

**FILES.** `docs/features/request-attention.md` (new, 244 lines); `docs/README.md` (feature row + active-plan
row, `new-stuff-indicators` row re-labelled as superseded); `CONTEXT.md` (§ My desk: obligation, optional update,
Dismiss all, outcome row — each with `_Avoid_`; responsibility-split entry now points at the contract);
`docs/features/new-stuff-indicators.md` (superseded banner); `docs/plans/work-activity-redesign-plan.md`
(refinement note naming what D1/D5/D7/D10 become).

**TESTS.** `bash scripts/check-user-facing-terminology.sh` → `check-user-facing-terminology: ok`. Relative links
from the new document resolved by hand: all five targets exist. No code touched, so no suite was run.

**FINDINGS.**
- `NewStuffCubit` no longer exists in the client, so `features/new-stuff-indicators.md` documented a retired
  mechanism — including "the active tab hides its navigation dot", which the new contract reverses. Banner added
  rather than deletion, to keep the history.
- The contract had to state its own status carefully: it describes both shipped and unshipped behaviour, so it
  says explicitly that a disagreement with code means either a defect or an unshipped feature, and the plan
  decides which.

**DECISIONS.** Recorded today's missing `×` on `helping` / `watching` outcome rows inside the contract as a known
defect rather than writing the rule as if it already held.

**REMAINING.** None for U01. Next: U02 characterization tests.

---
