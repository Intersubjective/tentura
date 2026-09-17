# Issue 162/180 implementation journal

Plan: `docs/plans/issue-162-180-review-package-state-plan.md` (revision 3)
Issues: #162 (package state invisible → HUD/checklist loop), #180 (leaver reviews block send)
Objective: make the reviewer's package state the UI's primary variable; optional = formerCommitter; drop auto-close on last send; notify author once when required packages are in; announce reopen.

## Run identity

- Repository: `/home/vader/MY_SRC/tentura`
- Branch: `fix/162-180-review-package-state`
- Starting HEAD: `ba996a3a82b01ad3487e9e62887105fecb3f8174` (`docs(review): plan the review package state and optional reviewers`)
- Overseer started: 2026-09-18T00:14:33+02:00
- Plan revision 3, decisions D1–D19 acknowledged.
- Escalation path at start: Astra (`gpt-6-astra` via `codex` 0.154.0) is installed; **rationed** (see below). Substitute if Astra unavailable: Opus 5 `--effort high`. Do not probe Astra until a rationed slot is spent.

## Baseline (verbatim, UNIT 00)

```
ba996a3a82b01ad3487e9e62887105fecb3f8174
fix/162-180-review-package-state
```

```
m0174.dart
m0175.dart
_migrations.dart
5:version: 7.15.0
flutter_bootstrap.js?v=7.15.0
67:const kDefaultMinClientVersion = '7.10.0';
```

Drift vs plan §3: **none**. `m0176` absent. `_autoCloseReviewWindow` still present at `evaluation_case.dart:1494` and `:1500`. Stop conditions not tripped.

## Pre-existing worktree (UNTOUCHABLE — never stage, reset, stash, or overwrite)

Modified:
- `.serena/project.yml`
- `docs/plans/constellation-pin-badge-zoom-lod-implementation-journal.md`

Untracked (non-exhaustive; all `??` at start): `CLAUDE.local.md`, `dart-defines`, many `docs/plans/*` (other plans/reviews/journals), `graph-ego-neighbors-layout-issue.md`, `key.fb`, `leo.key`, `out.key` (treat as secrets), `packages/image_cropper_for_web/build/`, `product_testing_*.md`, `tg_style_research.md`.

This plan's journal is the only new file UNIT 00 may add.

## Astra ration (user constraint)

Quota: ~3–4 uses until 06:00 CEST 2026-09-18, then ~3–4 more after reset. Usual fallback (Opus-high substitute, then overseer) still applies if a spent slot fails closed.

**Spend as inner executor, not as default solver.** Composer scout/verify still wrap every unit.

| Slot | When | Unit | Why |
|------|------|------|-----|
| A1 | current quota | UNIT 05 inner | transactional last-send nudge, idempotent `sourceEventKey`, concurrency PG — races + attention boundary |
| A2 | current quota | UNIT 10 inner | checklist is #162's primary surface: local skip, post-send stay+refresh, Flutter list at 360px×2.0 |
| A3 | current quota | UNIT 12 inner | HUD/banner nine-state × role × `allRequiredSent` matrix; deleting the getters that caused the loop |
| A4 | hold | emergency remediation of A1–A3 only | do not spend on 03/09/13 |
| B1–B3 | after 06:00 | Astra *review* of 10, 12, 05 (then 03) if already landed; else remaining ASTRA-inner units first | independent second look at the error-prone units |
| B4 | hold | UNIT 16 e2e/closeout defect inner | only if web e2e or PG closeout is red |

Opus-low inner for: 01, 02, 03, 04, 06, 07, 08, 09, 11, 13, 14, 15.
UNIT 03 is semantically hard (#180) but the plan ships literal code; Opus implements, overseer reads the diff line-by-line, Astra reviews after reset if the unit looked messy.
UNIT 11 is hard-class (D12 ambiguous error); Opus inner, overseer reads closely.
If Opus is unavailable: routine units degrade to Composer-only implement+verify; park hard units.

## Unit checklist

- [x] UNIT 00 journal and baseline — routine — overseer — complete
- [ ] UNIT 01 drop auto-close — hard (close paths) — Opus inner
- [ ] UNIT 02 m0176 `sent_at` + context — hard (many hops, PG) — Opus inner
- [ ] UNIT 03 optional targets / counters — hard (D6/D7) — Opus inner; Astra review later
- [ ] UNIT 04 GraphQL + client schema — routine — Opus inner
- [ ] UNIT 05 author nudge — hard (races, idempotency) — **ASTRA inner**
- [ ] UNIT 06 reopen announces — hard (tx order) — Opus inner
- [ ] UNIT 07 l10n keys — routine — Opus inner
- [ ] UNIT 08 `ReviewPackageState` — routine — Opus inner
- [ ] UNIT 09 client data/role/context — hard (DTO hops, codegen) — Opus inner
- [ ] UNIT 10 checklist UI — hard (Flutter, #162) — **ASTRA inner**
- [ ] UNIT 11 paused/closed classify — hard (D12) — Opus inner
- [ ] UNIT 12 HUD + banner — hard (#162 loop) — **ASTRA inner**
- [ ] UNIT 13 My Work cards — hard — Opus inner
- [ ] UNIT 14 author dialogs + Updates — medium — Opus inner
- [ ] UNIT 15 release 7.16.0 — routine — Opus inner
- [ ] UNIT 16 closeout — hard (PG + web e2e) — overseer matrix; Astra only if red

Never parallelize 02/03/04 or 09/10. Never skip or merge.

## Verification commands (plan)

See each unit's Verify block. All local `dart test` / `flutter test` / `check-custom-lints.sh` go through `scripts/run_with_test_cleanup.sh`. Do not wrap `run_client_integration_web_local.sh`. Do not use `flutter analyze` for custom lints. Generated files (`*.g.dart`, `_g/`) are never committed (D18).

## Unresolved decisions / blockers

None at start. Product decisions D1–D19 are frozen.

## UNIT 00 — complete — 2026-09-18T00:15:00+02:00

COMMITS: (pending this file)
TESTS: n/a — journal + baseline only; commands recorded above
FILES: `docs/plans/issue-162-180-review-package-state-journal.md`
FINDINGS: baseline matches §3; `_autoCloseReviewWindow` still live; no `m0176`; client dirty files from an earlier snapshot (`beacon_fact_composer_sheet.dart`, `test_ids.dart`, `basic_chat_body.dart`) are **not** dirty now — current `git status --short -- packages/client packages/server` is empty
REMAINING: none for UNIT 00; next is UNIT 01 sandwich

---

## Manager notes

Workers: read this journal fully before inspecting or editing. Append a checkpoint after meaningful progress. Append a final entry tagged `scout` / `inner` / `verify` / `finisher` before exit. Do not touch UNTOUCHABLE paths. Do not push. Do not invent user-facing strings. Owns lists in the plan are exclusive.

Prompt/log scratchpad (outside repo): `/tmp/overseer-162-180/`
