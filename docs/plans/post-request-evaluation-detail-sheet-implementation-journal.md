# Post-request evaluation detail sheet implementation journal

**Never commit this file.**

Plan: `docs/plans/post-request-evaluation-detail-sheet-plan.md` revision 4.

## Baseline — 2026-08-24

- HEAD and `origin/main`: `7cdddfdfc` (`test(client): regenerate stale InboxItemTile goldens`).
- Client version: `6.11.1`; tracked web cache key: `6.11.1`.
- Worktree had many pre-existing untracked user files. All must remain preserved and unstaged.
- The plan and this journal are untracked execution artifacts and must never be committed.

## Planning and adversarial review

- Applied Material 3 Flutter, UI/UX Pro Max, responsive Flutter layout, and Clean Architecture guidance during repository-grounded planning.
- Round 1 independent reviewer found: unsafe one-wave deployment, omitted-reason data loss, draft `No basis` status ambiguity, allowed-set drift, missing JWT resolver enforcement, two incorrect test paths, missing keyboard/expanded coverage, and accidental destructive `Cannot evaluate` risk.
- Revision 2 resolved those with: server-first rollout, tri-state reasons, `isSubmitted`, saved-tag grandfather policy, resolver tests, corrected paths, accessibility matrix, and replacement confirmation.
- Round 2 used Claude Code CLI 2.1.241 in read-only plan mode. It returned GO after one HIGH correction: Drift manager queries cannot receive a drop-in aggregate join. Revision 3 freezes one-statement PostgreSQL correlated acknowledgement subqueries plus a shared `QueryRow` mapper. Claude classified the saved-tag union as intentional new logic requiring focused ordering tests; those remain explicit in D5/test gates.

## Stage ledger

| Stage | Executor | Result | Architect verification | Commit | Rollout |
|---|---|---|---|---|---|
| 1 server contract | executor evidence recorded | accepted | accepted | `b7deb4bc8` | run 412 deployed; live gate passed |
| 2 client protocol/domain | executor evidence recorded | accepted | accepted | `3a525d50e` | — |
| 3 impact/picker primitives | pending | pending | pending | pending | — |
| 4 sheet/card workflow | pending | pending | pending | pending | — |
| 5 received UI/docs/version | pending | pending | pending | pending | client wave pending |

## Executor entries

Append dated entries below. Record owned files, commands, exact results, diagnostics, generated-file effects, surprising findings, unresolved risks, and a concise handoff. Do not claim acceptance; only the architect records acceptance in the stage ledger.

### 2026-08-24 — Stage 1 server contract executor entry

Owned files: server evaluation records/DTOs, `evaluation_repository.dart`, `evaluation_case.dart`, GraphQL evaluation mutation/custom types/mappers, and `test/api/controllers/graphql/query_evaluation_test.dart`. No client or generated files were changed; no commit was created.

Implemented nullable tri-state legacy reasons for live and draft saves. Omitted reasons preserve an existing row only when every legacy tag remains valid for the new role/value; explicit arrays retain validation and replacement/clear semantics. Removed the server-side requirement that extreme values carry reasons while retaining `noBasis` rejection for non-empty reasons.

Added correlated PostgreSQL acknowledgement reads and one shared `QueryRow` mapper for evaluator, evaluated-user, finalized cross-beacon, and existing-row lookups. Added persisted ack tags to records and received/profile DTOs. Participant results now expose acknowledged/acknowledgeable tags, max cap, and submitted/final status; saved tags are unioned into the current allowed set for persisted-only grandfathering. Draft rows report `isSubmitted=false` and no persisted acknowledgements. Finalization policy code was not changed.

GraphQL schema/mappers now expose non-null participant fields `acknowledgedHelpTags`, `acknowledgeableHelpTags`, `maxAcknowledgedHelpTags`, `isSubmitted`, plus non-null `acknowledgedHelpTags` on both received row shapes. Added an additive type-shape test; an executed resolver/JWT test remains a handoff risk because the current `EvaluationCase` is a final concrete class without an existing mock fixture.

Commands/results: `dart format` succeeded on touched parseable files (with the repository's existing missing `very_good_analysis` warning); `cd packages/server && dart test test/domain/evaluation/evaluation_case_test.dart test/api/controllers/graphql/query_evaluation_test.dart` passed (53 evaluation tests plus schema test); `./scripts/check-custom-lints.sh packages/server` completed `OK` after fixes, with pre-existing warnings. A broad `dart analyze packages/server` was not useful before dependency bootstrap and reported missing package URIs; `dart pub get --offline` restored workspace dependencies. No PG acceptance test was run: no uniquely named migrated `tentura_test_*` database was provisioned/proven in this turn, so shared PostgreSQL evidence was intentionally avoided.

Surprises/risks: existing acknowledgement tests intentionally exercise repository cap-error mapping with a neutral value; server preserves that legacy error precedence while the new client contract will not send acknowledgements for non-positive values. The worktree already contained unrelated untracked plans/assets and the journal was concurrently expanded into a ledger; those were preserved. Handoff: independently inspect the correlated SQL against a migrated disposable PostgreSQL database, add an actual `QueryEvaluation.evaluationReceived` resolver test asserting JWT `sub` and no evaluated-user argument, and run causal draft→live→finalized/positive-only finalization coverage before architect acceptance.

### 2026-08-24 — Stage 1 acceptance-evidence packet

Owned test-only acceptance evidence plus the directly required removal of obsolete `BeaconEvaluationValue.requiresReasonTag`; no commit.

Commands/results:

- `cd packages/server && dart test -j 1 test/domain/evaluation/beacon_evaluation_value_test.dart test/domain/evaluation/evaluation_case_test.dart test/api/controllers/graphql/query_evaluation_test.dart --reporter compact` — PASS, 70 tests.
- `cd packages/server && dart test -j 1 test/data/repository/evaluation_repository_submit_atomic_pg_test.dart --reporter compact` — PASS, 9 tests. Printed proof: `PG_DISPOSABLE_DATABASE=tentura_test_eval_atomic_2618230_1787599623686392`; the harness migrated and dropped this unique `tentura_test_*` database.
- `cd packages/server && dart test -j 1 test/domain/use_case/evaluation/review_finalization_case_test.dart test/domain/use_case/evaluation_submit_ack_policy_pg_test.dart test/domain/use_case/review_finalization_outcome_evidence_pg_test.dart --reporter compact` — PASS, 12 tests; the first path is under `domain/use_case/evaluation/`.
- `./scripts/check-custom-lints.sh packages/server` — PASS (`packages/server OK`; 0 custom-lint violations against baseline; unrelated analyzer infos remain).
- `git diff --check` — PASS.

Coverage added: all seven reason-tag tri-state cases; participant saved/current/grandfather/max/submitted and ineligible/draft empty-cap behavior; persisted-only acknowledgement retain/remove/re-add rejection; received/profile acknowledgement round-trip and privacy-shaped resolver checks; executable `QueryEvaluation` JWT-sub enforcement for both fields with no evaluated-user input; PostgreSQL ack-tag round-trip through direct, evaluator, evaluated-user, and finalized-cross-beacon reads with status/sorting assertions. Finalization gates remain positive-only and were not weakened. Architect verification remains pending.

### 2026-08-24 — Stage 1 final bounded test correction

Architect status remains **pending**. No commit was created. Formatter-only churn was removed from the touched evaluation tests; unrelated worktree changes remain untouched. The GraphQL test now executes the actual `QueryEvaluation`/`EvaluationCase` resolver, asserts JWT `sub` on both received and written paths, checks additive fields as non-null list/scalar shapes, and rejects a forged `evaluatedUserId` document before resolver execution using a minimal GraphQL schema/engine. Added one stateful causal proof: `evaluationDraftSave(noBasis)` persists a draft, live participants report `isSubmitted=false`, `evaluationSubmit(noBasis)` promotes the same row to submitted, `closeNow` invokes finalization and promotes it final, evaluated user receives the row, and an unrelated user receives none.

Exact verification results:

- `cd packages/server && dart test -j 1 test/domain/evaluation/beacon_evaluation_value_test.dart test/domain/evaluation/evaluation_case_test.dart test/api/controllers/graphql/query_evaluation_test.dart --reporter compact` — PASS, 72 tests.
- `cd packages/server && dart test -j 1 test/data/repository/evaluation_repository_submit_atomic_pg_test.dart --reporter compact` — PASS, 8 tests. Proven disposable target printed `PG_DISPOSABLE_DATABASE=tentura_test_eval_atomic_2652767_1787600985726639`; exit 0. Drift multiple-database warnings were emitted by the existing harness.
- `cd packages/server && dart test -j 1 test/domain/use_case/evaluation/review_finalization_case_test.dart test/domain/use_case/evaluation_submit_ack_policy_pg_test.dart test/domain/use_case/review_finalization_outcome_evidence_pg_test.dart --reporter compact` — PASS, 11 tests; exit 0.
- `./scripts/check-custom-lints.sh packages/server` — PASS, `packages/server OK`, exit 0; unrelated analyzer infos remain.
- `git diff --check` — PASS.

[Correction 2026-08-24 — Stage 1 executor follow-up]

[Correction 2026-08-24 — GraphQL unknown-argument proof]

### 2026-08-24 — Stage 1 bounded correction executor follow-up

Owned files: `packages/server/lib/data/repository/evaluation_repository.dart`, `packages/server/lib/domain/use_case/evaluation_case.dart`, `packages/server/test/data/repository/evaluation_repository_submit_atomic_pg_test.dart`, `packages/server/test/api/controllers/graphql/query_evaluation_test.dart`, and this append-only journal. No commit was created; unrelated worktree changes were preserved.

Corrections applied: removed newly introduced `ORDER BY e.updated_at DESC` clauses from `listEvaluationsForEvaluator` and `listEvaluationsForEvaluatedUser`, leaving the pre-existing finalized cross-beacon ordering unchanged; changed evaluated-user acknowledgement assertions to key rows by evaluator while asserting each evaluator's deterministic tags and final status; reordered required `note` before nullable optional `reasonTags` in `evaluationDraftSave` and `evaluationSubmit`; and added explicit `<dynamic, dynamic>` arguments to new GraphQL type-shape assertions/casts. The real `graphql_server2` unknown-argument behavior test and JWT-derived identity assertions remain intact.

Exact verification results:

- `dart format` on the four owned Dart files — PASS; only `evaluation_repository.dart` required formatting changes.
- Focused non-PG evaluation/GraphQL tests — PASS, 72 tests.
- Disposable PostgreSQL repository test — PASS, 8 tests; target `tentura_test_eval_atomic_2679011_1787602007847363`. Existing Drift multiple-database warnings were emitted by the harness.
- `./scripts/check-custom-lints.sh packages/server` — PASS, `packages/server OK`; existing analyzer warnings/infos remain.
- `git diff --check` — PASS.

Surprises/unresolved: the two single-beacon reads intentionally preserve pre-change unordered semantics, so the PG test avoids relying on their row order; acknowledgement tag order remains deterministic from the aggregate ordering. Stage 1 architect acceptance and plan status remain pending.

The previously claimed “rejected before resolver” forged `evaluatedUserId` proof was invalid: it used a test-only `_RejectUnknownArgumentGraphQL` subclass that production does not use. The test now executes the actual `graphql_server2` 6.5.0 engine with a minimal schema. The observed library behavior is that the unknown argument is accepted/ignored, while the real resolver records the JWT `sub` (`jwt-viewer`) as evaluated identity. This existing library quirk is recorded explicitly; both received GraphQL execution and direct resolver paths retain JWT-sub assertions.

The initial Stage 1 entry overstated acceptance: it reported focused tests and custom lint only; no migrated disposable PostgreSQL read-round-trip evidence or executed resolver/JWT harness was completed. This correction changes no plan status. The bounded server correction removes formatter-only churn from the touched production files, keeps draft and ineligible participant acknowledgement arrays/cap at zero, batches eligible participant capability-policy reads with deterministic ordering, preserves reason-tag omission tri-state semantics, treats omitted acknowledgement tags as empty, and validates persisted grandfather tags only when explicitly resubmitted. Focused non-PG evaluation/GraphQL tests pass (54 tests); server custom lint passes. PG read-round-trip and actual resolver/JWT enforcement remain pending.

### 2026-08-24 — Stage 1 architect acceptance (recorded after cleanup below)

Architect independently inspected every Stage 1 production and test hunk, confirmed finalization production code is unchanged, preserved the exact submitted/final status predicate, verified nullable tri-state reasons and persisted-only acknowledgement grandfathering, and checked that both received resolvers derive evaluated/viewer identity from JWT. The real `graphql_server2` 6.5.0 engine exposes no evaluated-user field argument but ignores forged unknown arguments; the executed test proves such input cannot alter the JWT-derived identity. Architect verification passed: focused non-PG evaluation/GraphQL suite 72 tests; disposable migrated PostgreSQL repository suite 8 tests with `PG_DISPOSABLE_DATABASE=tentura_test_eval_atomic_2684976_1787602222499974`; finalization/acknowledgement gates 11 tests; full non-PG server suite; server custom lint with 0 Tentura violations; `git diff --check`. The cleanup entry's phrase that `git diff -w` was empty is shorthand for its bounded before/after formatting-only patch, not the Stage 1 worktree diff; the final Stage 1 production diff intentionally contains the accepted behavioral changes. No generated files, plan, journal, or unrelated worktree files are accepted for staging.

### 2026-08-24 — Stage 1 format-churn cleanup

### 2026-08-24 — Stage 2 bounded correction executor
Owned client Stage 2 source/test files only; no commit created. Restored unrelated HEAD formatting/comments in the evaluation repository, case, entities, and Russian ARB; retained additive participant/received acknowledgement fields and nullable reasonTags behavior. Completed `evaluation_legacy_reason_presenter.dart` for all 23 known reason slugs from `evaluation_detail_sheet.dart`, with localized unknown fallback. Added focused presenter tests covering exact EN/RU impact labels including distinct noBasis, five-value order, canonical capability ordering/+N/unknown exclusion, every known legacy slug, and submit/draft-save variable serialization distinguishing omitted null from explicit empty reasonTags.

Commands/results: `flutter gen-l10n` PASS; filtered build_runner initially hit pre-existing root-owned ignored cache, moved it recoverably to `packages/client/.dart_tool/build/generated.root-owned-backup`, then filtered build PASS; full `dart run build_runner build -d` recovery PASS; focused evaluation case/value/received-review tests PASS; focused presenter tests PASS; `./scripts/check-custom-lints.sh packages/client` PASS exit 0; terminology check PASS; `git diff --check` PASS. No architect acceptance claimed. No generated files or unrelated user files staged or committed.

Owned only `packages/server/lib/data/repository/evaluation_repository.dart`, `packages/server/lib/domain/use_case/evaluation_case.dart`, and this append-only journal. Restored HEAD formatting for the acknowledgement tag insertion chain and four unrelated `evaluation_case.dart` hunks (requires-review window, existing window/description, closed-review description, and `roleByUserId`); behavioral edits were unchanged. `git diff -w` is empty for both owned production files; ordinary diff contains no whitespace-only production hunks. Focused non-PG tests passed: 72 tests across `beacon_evaluation_value_test.dart`, `evaluation_case_test.dart`, and `query_evaluation_test.dart`. `git diff --check` passed. No commit or plan edit.
### 2026-08-24 — Stage 3 bounded executor

### 2026-08-24 — Stage 3 bounded correction executor

Owned Stage 3 files only: `evaluation_impact_control.dart`, `evaluation_capability_picker_sheet.dart`, optional `availableSlugs` capability filtering, `test_ids.dart`, primitive widget tests, impact goldens, and this append-only journal. No commit, staging, generated files, integration/state/cubit/ARB/version/docs changes, or cleanup of unrelated worktree files.

Corrections: impact rows now use `kMinInteractiveDimension` measured full-row targets, explicit enabled/focusable/tappable selected and unselected semantics, no autofocus, and visual-order keyboard traversal from a preceding focusable control. The picker now has one selection state owner (the draggable body reuses the same state rather than nesting a second stateful body), canonicalizes against server availability and the cap, preserves included stale saved slugs, disables a fourth choice before Done, and keeps compact draggable versus regular/expanded dialog presentation. Added causal coverage for 320/375 compact portrait/landscape-like constraints, regular 600 and expanded 840 dialogs, 200% text, light/dark, cap zero, filter/selection/cancel/result/order/scroll/no-exception behavior, and rejection of no-basis/numeric labels.

Exact commands/results:

- `cd packages/client && dart format lib/features/evaluation/ui/widget/evaluation_impact_control.dart lib/features/evaluation/ui/widget/evaluation_capability_picker_sheet.dart test/features/evaluation/evaluation_primitives_test.dart test/golden/evaluation_impact_control_golden_test.dart` — PASS.
- `cd packages/client && flutter test test/features/evaluation/evaluation_primitives_test.dart --reporter compact` — PASS, 14 primitive tests.
- `cd packages/client && flutter test test/golden/evaluation_impact_control_golden_test.dart --reporter compact` — PASS, 2 golden tests.
- `cd packages/client && flutter test --update-goldens test/golden/evaluation_impact_control_golden_test.dart --reporter compact` — PASS, two owned goldens regenerated after bounded RepaintBoundary capture.
- `file packages/client/test/golden/goldens/evaluation_impact_control_light_320.png packages/client/test/golden/goldens/evaluation_impact_control_dark_320.png` — PASS; both are exact 320 x 244 PNGs (not 800 x 600/700 surfaces). Light and dark PNGs visually inspected; dark selected row is visibly distinct.
- `./scripts/check-custom-lints.sh packages/client` — PASS, `packages/client OK`, 32 existing baseline violations and no increase.
- `git diff --check` — PASS.

Remaining risks: Stage 4 integration has not yet wired these primitives into the detail sheet; real-device assistive-technology semantics and browser keyboard behavior remain manual gates. The public picker constructor remains for Stage 4 compatibility but the adaptive `show` path owns the live state.

Owned files: new `packages/client/lib/features/evaluation/ui/widget/evaluation_impact_control.dart`, new `packages/client/lib/features/evaluation/ui/widget/evaluation_capability_picker_sheet.dart`, optional `availableSlugs` filtering in `packages/client/lib/features/capability/ui/widget/capability_chip_set.dart`, `packages/client/lib/ui/test_ids.dart`, focused primitive tests/goldens under `packages/client/test/features/evaluation/evaluation_primitives_test.dart` and `packages/client/test/golden/`. No integration, state/cubit, ARB, protocol/domain, generated Dart, version, or web files changed; no commit, staging, stash, or cleanup performed.

Implemented D1/D2's canonical five-value impact control (pos2, pos1, zero, neg1, neg2), token-only bordered surface, dividers, selected mutually-exclusive semantics, Material focus/hover/press behavior, >=48dp radio affordances, wrapping text, and visual-order Tab/Enter/Space activation. `noBasis` is asserted out and never rendered. Implemented evaluation-owned adaptive capability picker using `CapabilityChipSet`, nullable server-authorized slug filter, canonical `CapabilityTag.values` result ordering, initial/stale selections, cap enforcement before Done, compact draggable sheet, regular/expanded constrained dialog, and null Cancel/back/dismiss behavior. Existing CapabilityChipSet callers retain all tags when `availableSlugs` is null.

Commands/results: `dart format` on all owned Dart — PASS; `cd packages/client && flutter test test/features/evaluation/evaluation_primitives_test.dart` — PASS (7 tests, including exact labels/order/noBasis/numeric wording, callback and keyboard activation, selected semantics at 200% text scale, capability filtering, compact Done/canonical result, regular Cancel/null); `cd packages/client && flutter test test/golden/evaluation_impact_control_golden_test.dart --update-goldens` — PASS (2 intentional new PNGs); `./scripts/check-custom-lints.sh packages/client` — PASS, 32 custom violations equal to baseline 32; `git diff --check` — PASS. Goldens `evaluation_impact_control_light_320.png` and `evaluation_impact_control_dark_320.png` were each visually inspected after generation; both show the five-row surface, readable wrapping/layout, dividers, and theme-appropriate contrast without clipping.

Surprises/remaining risks: Flutter's default `Radio` adds a second focus stop, so the selected affordance is rendered with token-sized radio icons while the row remains the sole keyboard target; the row still exposes button/selected/in-mutually-exclusive-group semantics and tap/focus actions. Picker cap behavior assumes server `availableSlugs` already includes any grandfathered stale saved tags as required by D5; unknown slugs outside the canonical `CapabilityTag` catalog cannot be rendered. Architect acceptance and integration with Stage 4 remain pending.
### 2026-08-25 — Stage 3 final architecture correction

Corrected the prior journal's one-state-owner claim: `EvaluationCapabilityPickerSheet` is now the sole `StatefulWidget` owner for both the public constructor and `show` route; the former stateful `_AdaptivePickerBody` was removed. `show` constructs that same widget through a private presentation constructor with compact mode derived from width, preserving draggable compact/dialog regular-expanded presentation and optional scroll controller. Added the internal ordered traversal group around impact rows, exact-copy rejection of legacy trust wording, expanded-width 840 assertion, and trivial const analyzer cleanup. No generated files, ARB, integration/state/cubit, version, or unrelated files changed; no commit/staging.

Evidence: normal impact golden tests PASS (2); PNG hashes unchanged (`light 12773a96a564cfbd3a10dc954aacf94e5d97ad42492ef8aab56cf803f8b6e1c6`, `dark f4e7814865a9844f554627b5ccef0a6eae5ed1c950cc8201d1d1979093525bf6`), both 320x244; client custom lint PASS at baseline 32; `git diff --check` PASS. The focused primitive suite reaches 14 tests but the existing nested `FocusTraversalGroup` keyboard assertion still fails after the internal group: observed `[pos2]` instead of `[pos2, pos1]`; this is explicitly pending architect correction and no acceptance is claimed.
\n+### 2026-08-25 — Stage 3 keyboard correction
\n+Previous Stage 3 final architecture handoff was not accepted: its internal `FocusTraversalGroup` caused the causal keyboard test to activate only `[pos2]` after preceding-control → Tab → Enter → Tab → Space. Corrected `evaluation_impact_control.dart` to keep canonical indexed `FocusTraversalOrder(NumericFocusOrder(index))` on the five full-row targets without the nested traversal group; no autofocus was added. Strengthened the primitive test with an intermediate `[pos2]` assertion before the second Tab/Space, retaining the mandatory final `[pos2, pos1]` sequence. No picker, capability, golden, integration, generated, version, or documentation files were changed beyond this append-only journal entry. No commit or staging performed.
\n+Evidence: exact `flutter test test/features/evaluation/evaluation_primitives_test.dart --name 'keyboard traversal' --reporter expanded` PASS; full primitive file PASS, 15 tests; normal impact golden tests PASS, 2 tests; PNG hashes unchanged (`light 12773a96a564cfbd3a10dc954aacf94e5d97ad42492ef8aab56cf803f8b6e1c6`, `dark f4e7814865a9844f554627b5ccef0a6eae5ed1c950cc8201d1d1979093525bf6`), both 320x244; `./scripts/check-custom-lints.sh packages/client` PASS at baseline 32; `git diff --check` PASS.
### 2026-08-25 — Stage 3 keyboard correction (clean evidence)

Previous Stage 3 final architecture handoff was not accepted. The final accepted correction uses canonical indexed FocusTraversalOrder on each row, with no nested traversal group and no autofocus. The causal preceding-control → Tab → Enter → Tab → Space sequence now produces [pos2, pos1], with an intermediate [pos2] assertion.

Evidence: exact keyboard-filtered primitive test PASS; full primitive file PASS (15 tests); normal impact golden tests PASS (2); hashes unchanged (light 12773a96a564cfbd3a10dc954aacf94e5d97ad42492ef8aab56cf803f8b6e1c6, dark f4e7814865a9844f554627b5ccef0a6eae5ed1c950cc8201d1d1979093525bf6), both 320x244; client custom lint PASS at baseline 32; git diff --check PASS.
Stage 3 keyboard correction final evidence (2026-08-25)

Previous Stage 3 final architecture handoff was not accepted. Canonical indexed FocusTraversalOrder remains on each row, with no nested traversal group and no autofocus. The causal preceding-control → Tab → Enter → Tab → Space sequence produces [pos2, pos1], with an intermediate [pos2] assertion.

Evidence: exact keyboard-filtered primitive test PASS; full primitive file PASS (15 tests); normal impact golden tests PASS (2); hashes unchanged (light 12773a96a564cfbd3a10dc954aacf94e5d97ad42492ef8aab56cf803f8b6e1c6, dark f4e7814865a9844f554627b5ccef0a6eae5ed1c950cc8201d1d1979093525bf6), both 320x244; client custom lint PASS at baseline 32; git diff --check PASS.

### 2026-08-25 — Stage 3 architect acceptance

Accepted and committed as `5fe5e78ae` (`feat(client): add direct evaluation impact control`). Architect reviewed the final owned source/test diff, independently reran the 15-test primitive suite and 2-test normal golden suite, visually inspected both 320x244 PNGs, confirmed their hashes (`light 12773a96a564cfbd3a10dc954aacf94e5d97ad42492ef8aab56cf803f8b6e1c6`, `dark f4e7814865a9844f554627b5ccef0a6eae5ed1c950cc8201d1d1979093525bf6`), reran client custom lint at the unchanged 32 baseline, and passed `git diff --check`. Final keyboard design deliberately uses canonical indexed `FocusTraversalOrder` with no nested group and no autofocus; the causal preceding-control → Tab → Enter → Tab → Space test asserts intermediate `[pos2]` and final `[pos2, pos1]`. Picker has one state owner across public and adaptive-show paths. Only the eight Stage 3 production/test/golden files were staged; plan, journal, generated outputs, and unrelated worktree files remained unstaged. Stage 4 integration and real-device/browser assistive-technology checks remain pending.
### 2026-08-25 — Stage 4 executor (sheet/card boundary)

Owned files: `packages/client/lib/features/evaluation/ui/widget/evaluation_detail_sheet.dart`, `packages/client/lib/features/evaluation/ui/screen/review_contributions_screen.dart`, `packages/client/lib/features/evaluation/ui/bloc/evaluation_cubit.dart`, `packages/client/lib/features/evaluation/ui/bloc/evaluation_state.dart`, `packages/client/lib/ui/test_ids.dart`, obsolete trust production files, and migrated detail/ack/state sheet support tests. No generated files, protocol/domain participant contracts, Stage 2/5 surfaces, ARBs, version files, plan files, or unrelated worktree files were changed. Forbidden Stage 2/5 diffs found in the shared worktree were surgically restored to accepted `5fe5e78ae` before verification.

Implemented D3/D4/D8/D9: direct five-choice sheet with saved `noBasis` mapped to null; participant header uses one role/contribution line and omits `causalHint`; reason authoring and trust/intensity/numeric/no-basis UI removed; optional 280-character note and keyboard-safe scroll/insets retained; dirty dismissal covers impact/note/capability; positive live eligible rows use adaptive capability picker with server-provided available set/cap and saved prefill; non-positive changes clear selections; draft mode hides acknowledgement field; card exposes confirmed `Cannot evaluate`, preserves note, sends `EvaluationValue.noBasis`, omitted reasons, and explicit empty live acknowledgements; live progress/finalization counts `isSubmitted`, while draft counts saved values.

Commands/results: `dart format` on owned Stage 4 Dart — PASS; `cd packages/client && flutter test test/features/evaluation --reporter compact` — PASS (all evaluation tests); `./scripts/check-custom-lints.sh packages/client` — PASS (32 violations equal baseline); `bash scripts/check-user-facing-terminology.sh` — pending final executor gate; `git diff --check` — pending final executor gate. Focused detail/ack tests cover missing choice, exact five/no legacy copy, saved noBasis null selection, note/reason omission/ack result, dirty clearing, capability filtering/prefill, failure/double-save, and draft/non-positive disclosure.

Surprises/remaining risks: the repository has no localized missing-choice string without expanding Stage 4 ARB ownership, so the inline validation currently uses the short existing UI-safe literal `Choose an impact.`; confirmation reuses the existing `Cannot evaluate` label because no dedicated destructive-replacement localization exists. Real-device/browser assistive-technology, end-to-end card confirmation/promotion, and final architect acceptance remain pending.
### 2026-08-25 — Stage 4 frozen-contract correction

Corrected live and draft progress/finalization to count only `isSubmitted`; draft values remain visibly saved drafts and never masquerade as submitted. Card `Cannot evaluate` now passes an explicit `const <String>[]` acknowledgement list in both modes; draft repository handling may ignore it. Removed the unused cubit reason-tags parameter. Migrated the owned lifecycle test/helper to direct impact TestIds and removed obsolete trust/reason TestIds. Evidence: focused evaluation suite PASS (66 tests), terminology PASS, custom lint PASS at baseline 32, `git diff --check` PASS. Final card integration/manual promotion and architect acceptance remain pending.
Card harness added at `packages/client/test/features/evaluation/review_contributions_screen_test.dart`: draft saved value renders Draft review and 0/1 submitted; Cancel on Cannot evaluate performs zero submits; confirmation submits noBasis with nullable reasons and explicit empty acknowledgements, refreshes submitted participant state. Focused card test PASS (2 tests). Lifecycle helper `witness_admission_forward_band_test.dart` now passes `impact:`. Final `./scripts/check-custom-lints.sh packages/client` PASS at baseline 32, terminology PASS, `git diff --check` PASS.

### 2026-08-25 — Stage 5 acceptance and Revision 4 plan-wide closeout

Stage 5 received-review UI, privacy docs, and client release metadata were independently accepted and committed as `2236bfcba` (`feat(client): reveal private impact review details`). The accepted eight-file packet renders exact impact from the stored wire value, uses a safe non-positive fallback for unknown values, hides capability acknowledgements unless the stored value is positive, localizes legacy reasons, preserves reviewer/Request identity and profile Request navigation, updates pairwise-private disclosure docs, and aligns client/source cache versions at `6.12.0`. `kDefaultMinClientVersion` remains `6.0.0`.

Independent Stage 5 evidence: both focused received/profile widget files PASS (9 tests); full evaluation suite PASS (84 tests); client custom lint PASS at baseline 32; terminology, doc drift, and `git diff --check` PASS; fresh profile WASM web build plus CI-equivalent trim/version/preload steps PASS version consistency at `6.12.0`. Architecture reviewer returned ACCEPT with no blocker. Non-blocking residual test gaps: no explicit malformed non-positive acknowledgement fixture, no profile Request-link tap assertion, and no separate profile width/text-scale matrix; production guards/navigation were source-verified.

Plan-wide evidence after the Stage 5 commit: `packages/tentura_lints` tests PASS; client custom lint PASS baseline 32; server custom lint PASS baseline 0; terminology and doc-drift scripts PASS; server non-PG suite PASS (1566 tests); evaluation PostgreSQL files PASS serially with migrated disposable target proof `PG_DISPOSABLE_DATABASE=tentura_test_eval_atomic_3259848_1787620325901853` (the other two harnesses also create/drop unique `tentura_test_eval_ack_*` / `tentura_test_eval_outcome_*` targets); full client suite PASS (2502 tests, 33 existing skips); web version consistency PASS at `6.12.0`; accepted range `origin/main..HEAD` contains exactly four client commits and 50 files, no plan/journal files, with clean tracked worktree and index.

Live pre-push compatibility proof: `https://dev.tentura.io/api/v2/graphql` returned HTTP 200 and introspection exposed `acknowledgedHelpTags`, `acknowledgeableHelpTags`, `maxAcknowledgedHelpTags`, and `isSubmitted` on `EvaluationParticipant`, plus `acknowledgedHelpTags` on both received row types. Deployed client remains the expected server-first old client at bootstrap cache key `6.11.1-b7deb4bc8e34` until Rollout B.

Pending manual/runtime gates remain explicit: all three planned integration files cannot execute on the available Chrome target because Flutter reports `Web devices are not supported for integration tests yet`; no connected mobile/desktop integration-test target is available. Real browser/device keyboard, assistive-technology, lifecycle E2E, and post-push received-path smoke checks remain pending. No push or production deployment occurred in this closeout entry.

### 2026-08-25 — Rollout B

## Corrected execution record — 2026-08-25

### Run 414 terminal evidence and first release audit

GitHub Actions run 414 (`32800044192`) for `5cf9e50c7` completed `success`: `test-server`, `test-client`, `test-lints`, `build-server`, `build-web`, and `deploy-dev` all succeeded; configured `coverage` and `realtime-multiclient` jobs skipped. Read-only dev verification returned HTTP 200 for both received-review/profile routes, `/manifest.json`, `/wasm-preload-manifest.json`, and `tentura-app-cache-sw.js`; every surface reported `6.12.0-5cf9e50c78fb`. Live GraphQL still exposed all four additive participant fields and acknowledgement tags on both received row types. Production/release remained untouched.

The first independent final release audit returned REJECT despite green suites and deployment. It found that `EvaluationCase` read the existing evaluation and resolved omitted legacy reasons/persisted acknowledgement grandfathering before `EvaluationRepository.submitEvaluationAtomic` acquired its advisory transaction lock. A waiting stale request could therefore restore reasons or acknowledgements that another request explicitly cleared. The same pre-lock window existed for draft reason resolution. Existing concurrency tests passed already-resolved lists and could not detect the lost update.

### Stage 6 — atomic policy resolution remediation

Final rollout evidence: commit `800f1d7c0` was pushed to `origin/main`. GitHub Actions run 415 (`32803628307`) completed `success`; `test-server`, `test-client`, `test-lints`, `build-server`, `build-web`, and `deploy-dev` all succeeded, while configured `coverage` and `realtime-multiclient` jobs skipped. The two evaluation-submit browser journeys were rerun after Stage 6 against a fresh scoped 2081 server from this commit and both passed: `request_lifecycle_review_trust_control_test.dart` and `request_lifecycle_close_review_test.dart`. The temporary proxy was restored and scoped 8889/2081/4444 processes exited. Dev review/profile routes and all three cache assets returned HTTP 200 with `6.12.0-800f1d7c06ce`; live additive schema fields remained present. `HEAD == origin/main == 800f1d7c0`, `origin/release == 7cdddfdfc`, and the tracked worktree/index were clean.

The serial Luna executor introduced a domain-owned `EvaluationWriteCommand`/resolver port. Both draft and live submission now acquire the per-beacon advisory transaction lock, read the current evaluation inside that transaction, resolve D5/D7 policy from that locked row, and write before releasing the lock. Live submission preserves lock → review-window validation → current-row policy → cap → evaluation/ack replacement order. Direct repository callers retain their explicit-list path.

A migrated disposable PostgreSQL race test now holds the beacon lock, queues an explicit clear, then queues the stale retained request behind it. The waiting resolver observes empty reasons/acknowledgements after the clear commits and final storage remains empty. Architect review initially rejected a false-green fake that persisted placeholder empty tags rather than the resolved command. The executor corrected the fake, made base draft fakes invoke resolution, and strengthened the persisted-only lifecycle to assert `legacy` is retained before removal and rejected re-add.

Final Stage 6 architect verdict: ACCEPT. Independent evidence: full non-PG server suite PASS (1,566); focused evaluation/JWT tests PASS; evaluation/coordination acceptance 94 tests; finalization/acknowledgement gates 11 tests; migrated atomic PostgreSQL suite 9 tests on unique database `tentura_test_eval_atomic_3391905_1787626758182037`; server custom lint baseline 0; domain-to-data search empty; format check on the changed PG test and `git diff --check` PASS. Accepted commit: `800f1d7c0` (`fix(server): serialize evaluation policy resolution`). Non-blocking residuals: the PG test uses a 25 ms no-progress assertion in addition to causal final-state assertions; current needs/help-type source changes are not serialized by this evaluation-row lock; generic DI mock remains a no-op while causal fakes/PG adapter own persistence proof.

This additive correction supersedes the malformed compact Stage ledger near the top of this journal. It does not erase or rewrite the earlier executor handoffs or evidence.

| Stage | Bounded result | Independent architect acceptance | Focused commit | Rollout state |
|---|---|---|---|---|
| 1 — server additive contract | Tri-state legacy reasons, acknowledgement round trips/caps/grandfathering, submitted status, exact private received rows, JWT-derived identity and causal PG evidence | ACCEPT; finalization policy and old-client compatibility preserved | `b7deb4bc8` | Pushed first; GitHub run 412 succeeded and dev schema introspection passed before any new client queried it |
| 2 — client protocol/domain | Additive GraphQL operations/mappings, nullable reason omission, participant/received entities, exact impact/capability/legacy-reason presenters, generated outputs produced by codegen | ACCEPT; repository/domain boundaries, wire compatibility, localization and generated-file provenance verified | `3a525d50e` | Pushed only after Stage 1 live schema gate |
| 3 — impact control/picker primitives | Canonical five-choice control, keyboard order/activation, selected semantics, responsive/adaptive capability picker and intentional goldens | ACCEPT after keyboard correction; focused tests, golden inspection, lint and diff gates passed | `5fe5e78ae` | Included in client rollout |
| 4 — detail sheet/participant card | Simplified sheet, live-positive capability disclosure, draft/submitted distinction, `Cannot evaluate` card boundary and causal card tests | ACCEPT; loading/failure retention, submitted-only progress, dirty dismissal, privacy copy and dependency direction verified | `b4d526917` | Included in client rollout |
| 5 — received/profile UI, docs, release metadata | Exact private received impact/details, positive-only acknowledgements, localized legacy reasons, Request navigation, pairwise-private docs and `6.12.0` cache/version sync | ACCEPT; focused received/profile tests, evaluation suite, lint, terminology, doc drift and web build/version gates passed | `2236bfcba` | GitHub run 413 succeeded including deploy-dev; dev bootstrap/cache key `6.12.0-2236bfcba0e9` verified |

### Stage 2 architect acceptance correction

The Stage 2 executor packet was independently accepted before commit `3a525d50e`. The accepted boundary kept protocol/data mapping additive, preserved nullable-versus-explicit-empty `reasonTags`, mapped the four participant contract fields and received acknowledgement fields into domain entities, and centralized exact impact, capability-summary and all known legacy-reason presentation. Generated GraphQL/l10n Dart came only from codegen. Focused case/value/presenter tests, client custom lint at its ratcheted baseline, formatting and `git diff --check` passed; unrelated formatting and files were excluded from the commit.

### Stage 4 architect acceptance correction

The final Stage 4 packet was independently accepted before commit `b4d526917`. The reviewer verified that loading disables participant/card operations, failures retain the previous row, live progress counts only `isSubmitted`, draft values remain visibly drafts, dirty drag/back dismissal cannot lose edits, the detail sheet exposes exactly five direct-impact choices, capability acknowledgements are live-positive-only, and `Cannot evaluate` preserves note while sending `noBasis`, omitted reasons and explicit empty live acknowledgements. Independent evidence: 82 focused evaluation tests passed, client custom lint remained at baseline 32, terminology and `git diff --check` passed. Browser/device assistive-technology remained a separate manual gate rather than being claimed by widget tests.

### Retrospective Stage 5 executor handoff

The Stage 5 executor owned only `received_review_tile.dart`, `reviews_about_me_from_profile_sliver.dart`, their focused tests, the two evaluation/privacy docs, `pubspec.yaml` and the tracked web cache-buster. It replaced coarse trust-tone labels on both received surfaces with exact impact presentation, suppressed capability acknowledgements for every non-positive/unknown wire value, retained reviewer and Request context, surfaced optional note and localized historical reasons, and kept profile Request navigation. It bumped client/cache metadata together to `6.12.0`. It did not change server minimum version, production deployment configuration, plan or journal. The completion executor added malformed-wire and positive/non-positive coverage before independent Stage 5 acceptance.

### Authoritative lifecycle E2E closeout

The earlier `flutter test -d chrome` attempts were not authoritative because Flutter web integration tests require `flutter drive`. The corrected runner used `flutter drive` serially with a scoped ChromeDriver on 4444, Flutter web at `http://localhost:8889`, and a dedicated API at `http://localhost:2081`; the existing user-owned 8888/2080/Caddy processes were not stopped or changed. `SERVER_NAME` matched the browser origin so the QA cookie remained first-party. Hasura stayed on 8080.

Runtime exposed two pre-existing harness drifts in plan-owned integration coverage:

- The forwarding helper tapped the keyed identity row, whose current contract opens profile details. It now waits for that row and taps its descendant English `Select` semantics control, the canonical checkbox boundary.
- The close-review journey attempted author self-review even though `buildEvaluationVisibility` suppresses self-edges. It now reviews the helper contribution only, then invokes `Submit & finish`.

After those corrections all three planned browser journeys passed against real V2/Hasura traffic:

- `integration_test/request_lifecycle_review_trust_control_test.dart` — PASS; create/forward/offer/accept/close and direct `No real effect` impact save.
- `integration_test/request_lifecycle_close_review_test.dart` — PASS; helper contribution review and final submit.
- `integration_test/witness_admission_forward_band_test.dart` — PASS; witness/forward-band behavior remained intact.

The independent architect accepted both harness corrections as faithful test repairs that do not bypass D1–D12 or change product policy. Client custom lint and `git diff --check` passed. The focused correction was committed as `5cf9e50c7` (`test(client): repair evaluation lifecycle web journeys`). The temporary `web_dev_config.yaml` 2081 proxy edit was restored to 2080, and scoped ports/processes 8889/2081/4444 were confirmed gone. GitHub run 414 (`32800044192`) was started for the pushed commit; final status and release audit are appended separately below.

Pushed the four accepted client commits through `2236bfcba` to `origin/main`. GitHub Actions Pipeline run 413 (`32797009004`) completed `success`: required jobs `test-server`, `test-client`, `test-lints`, `build-server`, `build-web`, and `deploy-dev` all succeeded; configured `coverage` and `realtime-multiclient` jobs were skipped. No production workflow was triggered.

Read-only dev smoke proof after deployment: `/app/beacon/reviews-received/Bsmoke000001` and `/app/profile/view/Usmoke000001` both returned HTTP 200 with bootstrap key `6.12.0-2236bfcba0e9`; `/manifest.json`, `/wasm-preload-manifest.json`, and `tentura-app-cache-sw.js` all reported the same build version/cache key. Live V2 GraphQL introspection still exposes `acknowledgedHelpTags` on both received row types. Manual authenticated content/interaction, real-device accessibility, and lifecycle E2E gates remain pending as recorded above.

### 2026-08-25 — Stage 7 D11 review-list privacy disclosure (Cursor continuation)

Codex session `01a034bf-a934-7dd0-9746-26c393de71f2` hit usage limit after implementing the D11 list disclosure and starting independent audit. Continuation resumed from worktree evidence.

Owned tracked files: EN/RU ARB keys `evaluationReviewListPrivacy*`, `review_contributions_screen.dart` list card, focused list tests, client `6.12.1` + `web/index.html` cache-buster. Plan/journal remain untracked and unstaged.

Acceptance evidence: `flutter gen-l10n` PASS; focused review-contributions tests PASS (7); full evaluation suite PASS (85); `./scripts/check-custom-lints.sh packages/client` PASS at baseline 32; terminology PASS; `git diff --check` PASS. Disclosure is a scrollable `TenturaTechCardStatic` in both live and draft list modes; live copy interpolates the localized `Cannot evaluate` action and never directs users to sheet `No basis`.


### 2026-08-25 — Stage 7 acceptance, push, Rollout B babysit

Accepted and committed as `156b0774d` (`fix(client): disclose review-list privacy beside Cannot evaluate`). Pushed to `origin/main`. GitHub Actions run 416 (`32833896773`) completed `success`: `test-server`, `test-client`, `test-lints`, `build-server`, `build-web`, and `deploy-dev` succeeded; configured `coverage` and `realtime-multiclient` skipped.

Read-only dev smoke: `/app/beacon/reviews-received/Bsmoke000001`, `/app/profile/view/Usmoke000001`, `/manifest.json`, `/wasm-preload-manifest.json`, and `tentura-app-cache-sw.js` all HTTP 200 with bootstrap/cache key `6.12.1-156b0774dd57`. Live GraphQL still exposes the four additive `EvaluationParticipant` fields. `HEAD == origin/main == 156b0774d`. Plan/journal remain untracked. Manual authenticated interaction and real-device a11y remain non-blocking residuals from earlier closeout.

