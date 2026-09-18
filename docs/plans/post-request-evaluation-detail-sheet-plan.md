# Post-request evaluation detail sheet simplification

**Status:** Revision 4; both adversarial reviews resolved, approved for serial execution.

**Source request:** `/home/vader/.codex/attachments/63610eab-2b83-494b-9b78-1cb8a5016e81/pasted-text-1.txt`

**Implementation journal (never commit):** `docs/plans/post-request-evaluation-detail-sheet-implementation-journal.md`

## 1. Goal and acceptance boundary

Replace Tentura's current two-stage, abstract-trust evaluation control with one vertical five-choice scale describing the effect of one concrete contribution to one Request. Keep the existing six wire values and review lifecycle. Remove reason-tag authoring without deleting historical reasons or breaking old clients. Show capability acknowledgements only after a positive choice and edit them in a separate adaptive picker. Put `Cannot evaluate` on each participant card, outside the detail sheet. After closure, reveal the exact impact, capability acknowledgements, note, and reviewer identity only to the evaluated person.

The work is complete only when all of these are true:

1. The sheet contains exactly five choices, in this order: `Helped a lot`, `Helped somewhat`, `No real effect`, `Hurt somewhat`, `Hurt a lot`.
2. No numeric score and no abstract question about trust in a person appears in authoring, participant-card status, or received-review UI.
3. New-client authoring contains no reason step, reason validation, or reason chips. Existing reason rows remain stored, valid old-client inputs remain accepted, and historical received reasons remain readable.
4. Capability acknowledgement is hidden for no choice, neutral, negative, draft-mode, or ineligible evaluator roles. For an eligible positive live review it is one compact row that opens the existing categorized picker, enforces the server-provided set and three-tag cap, reloads saved selections, and clears on a non-positive or `Cannot evaluate` transition.
5. `No basis` is not an impact choice. Every participant card exposes a separate `Cannot evaluate` action in draft and live modes, with confirmation before replacing existing content.
6. A draft row is visibly a draft in live review and is never counted or presented as submitted. Saving in live mode promotes it to submitted. Closure never silently drops a row that the UI called reviewed.
7. After review closure, the evaluated user can see reviewer identity, exact five-level impact, positive capability acknowledgements, note, and readable legacy reasons in both received-review surfaces. The same Request id under a different JWT cannot reveal those rows.
8. Compact, regular, and expanded layouts; 200% text scale; light/dark themes; keyboard focus/activation; and screen-reader selected state are covered by focused tests.
9. The client version and tracked web cache-buster agree.
10. The additive server schema is deployed and live before any client build that queries it is deployed.

### Non-goals

- Do not change evaluator eligibility, participant graph construction, review-window timing, finalization, trust-bin weighting, Close now rules, or capability-evidence scoring.
- Do not introduce another strength/intensity question or progressive rating step.
- Do not introduce a public score, aggregate person rating, comments/debate, or a `Request` domain entity.
- Do not drop `beacon_evaluation.reason_tags`, `reasonTags` GraphQL fields, reason localization, summaries, lineage fallbacks, or historical rows.
- Do not change the outer workflow: saving a participant row is separate from `Submit & finish`.
- Do not raise `kDefaultMinClientVersion`; the server contract is additive and old clients must remain usable.
- Do not edit generated Dart files by hand. Run code generation after source schema, GraphQL document, Freezed, or ARB changes.

## 2. Current-state findings

### 2.1 Client authoring

- `packages/client/lib/features/evaluation/ui/widget/evaluation_detail_sheet.dart` owns direction/intensity state through `EvaluationTrustSelection`, reason state and validation, note state, capability state, dismissal protection, and save.
- `packages/client/lib/features/evaluation/ui/widget/evaluation_trust_control.dart` asks for direction and then intensity. Its copy describes trust in the person, not the effect of a concrete interaction.
- `packages/client/lib/features/evaluation/domain/entity/evaluation_trust_selection.dart` exists only to support that UI and can be removed after all references move to `EvaluationValue?`.
- `EvaluationValue` already has six wire values: `noBasis=0`, `neg2=1`, `neg1=2`, `zero=3`, `pos1=4`, `pos2=5`.
- `evaluation_detail_sheet.dart` shows the full `CapabilityChipSet` inline and initializes acknowledgement state empty because `EvaluationParticipant` does not carry saved acknowledgement rows. Editing a saved review can therefore erase acknowledgements.
- `CapabilityChipSet` already groups and localizes the capability catalog and supports a selection limit, but it cannot filter the catalog to a server-authorized slug set.
- `ReviewContributionsScreen` uses one `submitOne` entry point. The cubit correctly chooses draft-save versus live-submit from `state.isDraftMode`, but participant rows do not expose their DB row status.

### 2.2 Server validation, persistence, and finalization

- `BeaconEvaluationValue` uses the same wire/DB encoding. Its display-scale interpretation is `-2..+2`; those numbers need not change or become user-facing.
- `_validateEvaluation` currently requires reason tags for `neg2`, `neg1`, and `pos2`, and validates supplied tags by evaluated role and sign.
- Both evaluation mutations already define `reasonTags` as a nullable list. The resolver currently collapses omission to `[]`, losing the distinction needed to preserve legacy data.
- `submitEvaluationAtomic` replaces `reason_tags` and acknowledgement child rows atomically. The acknowledgement cap is `kCapMaxTagsPerSubjectBeacon == 3`.
- `evaluationSubmit` permits non-empty acknowledgements only from author, committer, and former-committer evaluators, and only for `beacon.needs ∪ evaluated user's active help types`.
- `review_finalization_case.dart` emits outcome capability evidence only for finalized positive reviews from eligible evaluator roles. This remains the enforcement boundary and must not change.
- Evaluation repository reads do not join `beacon_evaluation_ack_tag`, so saved acknowledgement tags cannot be prefilled or returned to received-review APIs.

### 2.3 Draft/submitted ambiguity

- Open-Request evaluation drafts and live-review evaluations occupy the same unique evaluation row and differ by `BeaconEvaluationRowStatus`.
- Live participant loading can return a draft value, but `EvaluationParticipantResult` omits status. The client therefore presents a draft value with the same reviewed status as a submitted row.
- Finalization does not treat drafts as submitted and later removes/ignores them. A draft `No basis` can consequently look complete in live review and disappear at closure.

### 2.4 Received reviews and privacy

- `EvaluationCase.evaluationReceived` returns no rows while review is open and, after closure, selects rows where `evaluatedUserId == jwt.sub`.
- GraphQL `evaluationReceived(id)` accepts only a Request id. `evaluationsWrittenAboutMeBy(id)` accepts the review author's id; both derive the evaluated/viewer identity from JWT.
- `ReceivedReviewTile` already shows reviewer identity, collapsed trust tone, note, and raw reason slugs. The profile surface shows collapsed tone and note. Both omit acknowledgement tags and hide the difference between `pos1`/`pos2` and `neg1`/`neg2`.
- Product docs still say recipients receive summaries only and that strong ratings require reasons. That contradicts the shipped named-review API/UI and the requested pairwise reveal.

### 2.5 Other reason-tag consumers

- `evaluation_summary_rules.dart` aggregates `topReasonTags`; empty new rows already have deterministic behavior.
- `BeaconLineageSuggestionsCase` optionally uses the first positive reason tag. An empty list already falls back to the same reviewed-helpful suggestion without a reason argument.
- Cross-beacon received-review DTOs retain reasons. Therefore authoring can stop producing them without removing their schema or read path.

### 2.6 Deployment behavior

- A push to `main` runs `.github/workflows/pipeline.yml`, builds both web and server, and deploys dev after tests.
- `deploy.sh` extracts the new web archive before restarting the server/Hasura stack. A single push containing the new GraphQL-querying client and new server can briefly serve the client against the old schema.
- Rollout must therefore use two pushes: server additive contract first while the old client is rebuilt unchanged, then the client after the live schema is verified.

## 3. Frozen implementation contracts

### D1. Direct impact value and copy mapping

`EvaluationImpactControl` is controlled by `EvaluationValue?`. It accepts only the five evaluable values; `null` means no choice. `noBasis` is rejected by assertion and never rendered.

| Order | Domain value | Wire value | English label | Icon |
|---:|---|---:|---|---|
| 1 | `pos2` | `5` | Helped a lot | `keyboard_double_arrow_up_rounded` |
| 2 | `pos1` | `4` | Helped somewhat | `arrow_upward_rounded` |
| 3 | `zero` | `3` | No real effect | `remove_rounded` |
| 4 | `neg1` | `2` | Hurt somewhat | `arrow_downward_rounded` |
| 5 | `neg2` | `1` | Hurt a lot | `keyboard_double_arrow_down_rounded` |

`noBasis` remains wire `0`; its card result label is `No basis` and its action label is `Cannot evaluate`. No `-2`, `-1`, `0`, `+1`, or `+2` display strings are introduced.

The existing role-specific contribution prompt remains the sheet's only question:

- author: `evaluationPromptAuthor`
- helper/full: `evaluationPromptHelpOfferer`
- helper/handoff: `evaluationPromptHelpOffererHandoff`
- forwarder: `evaluationPromptForwarder`

Delete abstract trust-direction, intensity, preview, and reason-required UI copy only after `rg` proves no live references.

### D2. Impact control structure and accessibility

Create `evaluation_impact_control.dart` as one bordered Material surface containing five full-width rows separated by `TenturaHairlineDivider`.

Each row must have:

- an icon and text, so color is never the only signal;
- a 48dp-or-larger Material tap target with hover, pressed, and focus states;
- selected radio/check affordance and mutually-exclusive selected semantics;
- wrapping text with no fixed row height, `FittedBox`, horizontal scrolling, or text-scale override;
- keyboard traversal in visual order and activation by Enter/Space.

Use `context.tt`, `TenturaText`/theme text styles, `ColorScheme`, and existing adaptive-sheet primitives. Feature UI must not add raw colors, font sizes, numeric `EdgeInsets`, or numeric `BorderRadius`.

### D3. Detail-sheet composition

Refactor the sheet into small responsibilities:

1. `_EvaluationParticipantHeader`: avatar, display name, and one muted role/contribution line. Use `contributionSummary` when present; omit `causalHint` from this simplified sheet.
2. `EvaluationImpactControl`: the single five-choice question.
3. `_CapabilityAcknowledgementField`: a conditional one-row summary/action.
4. Note `TextField`: always visible, optional, maximum 280 characters, about three lines.
5. `_EvaluationRevealNotice`: draft or live pairwise privacy copy.
6. One primary `Save` button with inline missing-choice feedback and existing loading/double-submit protection.

Continue using `showTenturaAdaptiveSheet`, a scrollable body, safe areas, keyboard insets, and `TenturaSheetDismissGuard`. Rating, note, and capability changes all participate in dirty-dismiss protection.

When a saved `noBasis` row opens the detail sheet, initialize the impact control to `null`, not neutral. Closing without saving leaves it unchanged; saving any of the five choices replaces it.

### D4. Capability dynamic disclosure and picker

Show the capability field only when all are true:

1. the screen is in live review, not open-Request draft mode;
2. the chosen value is `pos1` or `pos2`;
3. `maxAcknowledgedHelpTags > 0` and `acknowledgeableHelpTags` is non-empty.

Before selection, show `+ Choose capabilities` plus chevron. After selection, show the first two localized names in canonical `CapabilityTag.values` order plus localized `+N`, for example `Transport, Pets +1`, plus the same chevron.

Add an evaluation-owned adaptive picker that embeds `CapabilityChipSet` and receives `initialSlugs`, `availableSlugs`, and `maxSelection`.

Add an optional `availableSlugs` filter to `CapabilityChipSet`; `null` preserves every existing caller. The picker uses `showTenturaAdaptiveSheet`: draggable/scrollable on compact constraints and constrained dialog presentation on regular/expanded constraints. `Done` returns a selection; Cancel/back/dismiss returns nothing and leaves the parent selection unchanged. The server-provided cap is passed to `maxSelection`, so a fourth choice is disabled before submit.

Changing `pos1 ↔ pos2` retains selections. Changing to `zero`, `neg1`, or `neg2` clears them and marks the form dirty. The participant-card `Cannot evaluate` operation explicitly submits an empty acknowledgement list. Reopening a saved positive row preloads saved tags.

### D5. Participant acknowledgement contract and allowed-set drift

Add non-null additive fields to GraphQL `EvaluationParticipant` and both live/draft DTO mappings:

- `acknowledgedHelpTags: [String!]!` — saved tags for this evaluator/subject row;
- `acknowledgeableHelpTags: [String!]!` — canonical sorted current allowed slugs plus grandfathered saved slugs;
- `maxAcknowledgedHelpTags: Int!` — `3` for eligible live evaluators, `0` otherwise;
- `isSubmitted: Boolean!` — true only for submitted/final row status, never draft.

For live eligible evaluators, calculate current allowed slugs from the existing server rule: `beacon.needs ∪ fetchActiveHelpTypes(beaconId, evaluatedUserId)`. Do not reproduce that formula in the client.

Grandfathering policy for allowed-set drift:

- Saved acknowledgement slugs are unioned into that row's validation set and participant response even if they have left the current allowed set.
- They may be retained or removed on the next save. A removed stale slug is no longer grandfathered and cannot be added again unless it re-enters the current allowed set.
- A caller cannot grandfather a new slug merely by sending it; the union comes only from the persisted row read before validation.
- Draft participants return empty acknowledgement arrays, cap `0`, and `isSubmitted=false`, because draft-save does not persist acknowledgements.

Add a causal drift test: save while allowed → remove from current allowed source → fetch still returns selected/available → unchanged resave succeeds → remove succeeds → later re-add attempt fails.

### D6. Read acknowledgement rows without a migration

Add `ackTags` with an empty default to `BeaconEvaluationRecord` and `CrossBeaconEvaluationRecord` (or the equivalent existing records used by the three reads).

Use a single PostgreSQL `customSelect` statement for each read, with a correlated acknowledgement subquery that returns a deterministic comma-separated `ack_tags_csv` (`string_agg(tag_slug, ',' ORDER BY tag_slug)` wrapped in `COALESCE(..., '')`). This avoids a second-statement snapshot race and does not require bolting a join onto Drift's manager API. Replace the two current manager reads with explicit selects and extend the existing cross-beacon select with the same correlated subquery:

- `listEvaluationsForEvaluator`
- `listEvaluationsForEvaluatedUser`
- `listFinalizedEvaluationsBetween`

Map each `QueryRow` through one small repository helper that reconstructs the existing evaluation record plus `ackTags` parsed from `ack_tags_csv`; do not duplicate row parsing among the three methods. The acknowledgement table's existing composite key supports the correlation. Keep every existing status predicate and ordering unchanged. Do not add or alter tables. The same statement-level snapshot provides participant prefill, single-Request received reviews, profile received reviews, and grandfathered validation.

### D7. Tri-state legacy reason compatibility

Keep the GraphQL `reasonTags` argument nullable and stop collapsing omission to `[]`. Change submit/draft use-case input to `List<String>? reasonTags` and resolve it only after evaluator/target authorization and the existing row have been loaded.

| Incoming state | Existing row | New value | Stored result |
|---|---|---|---|
| omitted/null | none | any five impact values | `[]` |
| omitted/null | existing | same or changed | preserve existing tags only if every tag is still valid for target role and new value; otherwise clear all |
| explicit `[]` | any | any five impact values | clear all |
| explicit non-empty | any | value that allows every tag | validate and replace |
| explicit non-empty | any | `noBasis` or incompatible role/sign | reject |

Remove the `requiresReasonTag` invariant on client and server: all five impact values accept no reasons. Retain `allowsReasonTag` and role/sign membership validation for non-empty legacy input. `noBasis` always resolves omitted legacy reasons to empty because no reason is compatible.

The new client omits `reasonTags` for sheet saves and card-level `Cannot evaluate`; it never sends `[]` merely because the authoring UI no longer exposes reasons. The server resolves and persists the appropriate list atomically. Old clients that explicitly send arrays keep replace semantics and validation. Apply the same tri-state behavior to draft-save. Do not remove reason output fields, storage, summaries, lineage behavior, or received-review display.

### D8. Draft/submitted presentation and promotion

Map `isSubmitted` into `EvaluationParticipant`.

- In draft mode, any `currentValue != null` is presented as a private saved draft.
- In live mode, only `isSubmitted` counts as reviewed and contributes to client progress/status.
- A live participant carrying a draft value shows `Draft — submit during review`, preloads its value/note/reasons when opened, and uses live `evaluationSubmit` on Save. The atomic upsert promotes it to submitted.
- Card-level `Cannot evaluate` in live mode also uses `evaluationSubmit`, promoting a draft `noBasis` to submitted.
- `Submit & finish` retains its server behavior. The UI must not call a draft row reviewed before promotion.

Add causal coverage for `draftSave(noBasis) → live participant isSubmitted=false → live submit(noBasis) → isSubmitted=true → close/finalize → evaluated user's received row exists`.

### D9. Card-level `Cannot evaluate` boundary

Refactor `_ParticipantTile` to contain a main participant/detail action plus a separate footer text action with its own key and semantics. At narrow width or large text scale the footer stays below a hairline; do not compete with `ListTile.trailing`.

- The action exists in draft and live modes and is disabled/selected when the effective row is already `noBasis` in the current mode.
- Tapping the main row after `noBasis` still opens the five-choice sheet with no impact preselected.
- If replacing any existing impact, note, legacy reason, or saved acknowledgement, first show a confirmation whose safe default is Cancel. Explain that the existing impact will be replaced and capability acknowledgements cleared. Keep the note unless the user later edits it.
- On confirmation, call the cubit with `value=noBasis`, omitted `reasonTags`, preserved note, and explicit empty acknowledgements for live mode.
- Disable actions while loading. Success reloads participants and shows `No basis`; failure leaves the prior row visible.

### D10. Received-review reveal and exact impact presenter

Add `acknowledgedHelpTags: [String!]!` to `EvaluationReceivedRow` and `EvaluationsWrittenAboutViewerRow`. Map joined acknowledgement tags through server DTOs/GraphQL and client GraphQL/domain entities. Render acknowledgements only for stored positive values; old non-positive rows may contain historical ack rows, but UI must not imply positive evidence.

Create one value presenter used by authoring status and both received surfaces. It maps the exact stored value to the five impact labels/icons, with `No basis` distinct. Keep `EvaluationReceivedTrustTone` only for other coarse-tone consumers; do not use it as the received label.

`ReceivedReviewTile` displays reviewer identity, exact impact, localized capability summary, note, and localized legacy reasons. Extract the old sheet's reason-slug switch into a legacy presenter so known values never render raw snake_case; unknown stored slugs use the existing fallback label.

The profile received-review row displays Request context, exact impact, localized capability summary, and note. It need not duplicate legacy reasons if that surface does not currently request them.

### D11. JWT-derived privacy enforcement and copy

Do not add an `evaluatedUserId` argument to either received query.

- Build/execute the actual `QueryEvaluation.evaluationReceived` GraphQL field with a mocked/recording `EvaluationCase`, authenticated arguments, and a Request id. Assert the schema field exposes no evaluated-user argument and the use case receives `jwt.sub`. `graphql_server2` 6.5.0 currently ignores an unknown forged field argument instead of rejecting the query, so execute that real-engine shape too and prove the forged value cannot alter the JWT-derived evaluated identity; do not use a test-only rejecting wrapper as production evidence.
- Do the equivalent JWT-subject assertion for `evaluationsWrittenAboutMeBy` while preserving its review-author id argument.
- In use-case tests, prove open window returns no rows; after closure user A receives only rows whose `evaluatedUserId=A`; user B using the same Request id cannot receive A's rows.
- Assert rows include reviewer identity, exact value, acknowledgements, note, and legacy reasons.

Live-sheet copy:

> After the review window ends, {name} will see your name, impact choice, capability acknowledgements, and note. Only you and {name} can see this review; it is not public or visible to other participants.

Draft-sheet copy:

> This is a private draft. It is not shared unless you save it during the review window.

Review-list privacy copy must say reviews are pairwise-private, become visible only to the evaluated person after closure, and are never public or visible to unrelated participants. It must direct users to each card's `Cannot evaluate` action instead of telling them to choose `No basis` in the sheet.

Update `docs/beacon-evaluation-principles.md` and `docs/Tentura_current_status_quo.md` to remove “summary only” and “strong values require reasons,” while preserving the prohibition on public or third-party named reviews.

### D12. Responsive and accessibility matrix

Focused widget tests cover 320px and 375px compact widths; regular tablet and at least 840px expanded desktop widths; portrait-like and landscape-like constraints; 200% text scale; light/dark themes; keyboard Tab order and Enter/Space activation; semantics label/role/enabled/selected state; scrollability above keyboard insets; one primary CTA; and safe cancel/dismiss.

Golden tests are useful for stable impact-control and picker primitives. Regenerate intentionally and have the architect inspect every changed PNG.

## 4. Exact production files

### Server/domain/data/API

- `packages/server/lib/domain/evaluation/beacon_evaluation_value.dart`
- `packages/server/lib/domain/evaluation/evaluation_reason_tags.dart` (retain; compatibility helpers only)
- `packages/server/lib/domain/entity/evaluation/beacon_evaluation_record.dart`
- `packages/server/lib/domain/entity/evaluation/cross_beacon_evaluation_record.dart`
- `packages/server/lib/domain/entity/gql_public/evaluation_participant_result.dart`
- `packages/server/lib/domain/entity/gql_public/evaluation_received_result.dart`
- `packages/server/lib/domain/entity/evaluation/evaluations_written_about_viewer_row.dart`
- `packages/server/lib/domain/repository/evaluation_repository_port.dart` if signatures require it
- `packages/server/lib/domain/use_case/evaluation_case.dart`
- `packages/server/lib/data/mapper/evaluation_mapper.dart`
- `packages/server/lib/data/repository/evaluation_repository.dart`
- `packages/server/lib/api/controllers/graphql/mutation/mutation_evaluation.dart`
- `packages/server/lib/api/controllers/graphql/custom_types.dart`
- `packages/server/lib/api/controllers/graphql/mappers/gql_v2_dto_maps.dart`
- keep `packages/server/lib/domain/use_case/evaluation/review_finalization_case.dart` production behavior unchanged unless a regression proves an in-scope fix is necessary

### Client protocol/domain

- `packages/client/lib/data/gql/schema.graphql`
- evaluation GraphQL documents: participants, draft participants, received, written-about-me, submit, and draft-save
- `packages/client/lib/features/evaluation/data/repository/evaluation_repository.dart`
- `packages/client/lib/features/evaluation/domain/use_case/evaluation_case.dart`
- evaluation value, participant, received, and written-about-viewer entities
- delete `packages/client/lib/features/evaluation/domain/entity/evaluation_trust_selection.dart`

### Client UI

- delete `packages/client/lib/features/evaluation/ui/widget/evaluation_trust_control.dart`
- add `evaluation_impact_control.dart`, `evaluation_capability_picker_sheet.dart`
- add value, capability, and legacy-reason presenters under `features/evaluation/ui/presenter/`
- `packages/client/lib/features/capability/ui/widget/capability_chip_set.dart`
- evaluation detail sheet, review contributions screen, cubit/state, received tile
- `packages/client/lib/features/profile_view/ui/widget/reviews_about_me_from_profile_sliver.dart`
- `packages/client/lib/ui/test_ids.dart`

### Localization/docs/versioning

- `packages/client/l10n/app_en.arb`, `app_ru.arb`; generated localization stays ignored
- `docs/beacon-evaluation-principles.md`, `docs/Tentura_current_status_quo.md`
- bump `packages/client/pubspec.yaml` from `6.11.1` to `6.12.0`
- set `packages/client/web/index.html` to `flutter_bootstrap.js?v=6.12.0`
- do not change `packages/server/lib/env.dart` or the minimum-client gate

## 5. Localization contract

Add EN/RU keys for the five exact impact labels and selected semantics; `Cannot evaluate`, `No basis`, private-draft/submitted statuses; destructive replacement confirmation; capability field/picker/Done/`+N`; live pairwise and draft-only disclosures; exact received-impact grammar; and selection-limit semantics. Reuse existing role prompts, capability names, reviewer roles, and legacy reasons. Delete obsolete trust/intensity/reason-authoring keys only when `rg`, l10n generation, and terminology checks prove them unused.

## 6. Test files and exact assertions

### Server

- `packages/server/test/domain/evaluation/beacon_evaluation_value_test.dart`: no reason required; sign predicates unchanged; `noBasis` rejects reasons.
- `packages/server/test/domain/evaluation/evaluation_case_test.dart`: tri-state matrix; participant saved/allowed/max/status; eligible/ineligible roles; stale-tag lifecycle; received exact details/privacy; draft promotion.
- reason-tag and summary-rules tests retain legacy compatibility/aggregation.
- add `packages/server/test/api/controllers/graphql/query_evaluation_test.dart` for executed resolver/JWT enforcement; add/update a separate additive type-shape test.
- repository atomic PG test proves acknowledgement round-trip through all three reads.
- correct finalization test path: `packages/server/test/domain/use_case/evaluation/review_finalization_case_test.dart`.
- keep `evaluation_submit_ack_policy_pg_test.dart` and `review_finalization_outcome_evidence_pg_test.dart` as enforcement-boundary gates.
- add/update lineage coverage for positive evaluation with empty reasons.

Every PG acceptance run uses one uniquely named, migrated `tentura_test_*` PostgreSQL database, prints/proves `current_database()`, runs `-j 1`, and cleans up. Shared `postgres` or an unmigrated empty database is not evidence.

### Client

- replace `evaluation_trust_control_test.dart` with impact-control tests for order, callbacks, no `noBasis`, no numeric/trust copy, semantics, keyboard, RU, 320px/200%, and expanded window.
- rewrite detail-sheet tests for validation/save/omitted reasons/note/noBasis/dirty/failure/double-save/keyboard insets.
- replace acknowledgement-chip tests with dynamic disclosure, prefill, cap, filter, stale saved tag, cancel/Done, retention/clear, and adaptive-window coverage.
- update repository/domain mapping tests and sheet support.
- add card live/draft/status/confirmation/success/failure/promotion tests.
- update `received_reviews_screen_test.dart` and correct profile path `packages/client/test/features/profile_view/reviews_about_me_from_profile_sliver_test.dart`.
- migrate `request_lifecycle_review_trust_control_test.dart`, `request_lifecycle_close_review_test.dart`, `witness_admission_forward_band_test.dart`, and E2E helpers to direct impact/separate picker.
- add/update and visually inspect stable primitive goldens.

## 7. Ordered serial execution packets

Every executor is a fresh Luna-model subagent, works alone, reads this resolved plan plus applicable rules and journal, owns only its packet, does not commit, and appends commands/results/surprises to the uncommitted journal. The architect independently inspects and verifies, requests corrections when needed, and commits only accepted work.

### Stage 1 — Additive server compatibility and reveal contract

**Ownership:** all server production/test files above; no client/docs.

1. Implement nullable tri-state reasons for live/draft without weakening non-empty legacy validation.
2. Add acknowledgement reads, participant allowed/saved/max/status, grandfather validation, and received ack fields.
3. Keep finalization policy unchanged and add causal authorization/finalization tests.
4. Add actual GraphQL resolver/JWT tests and additive schema tests.

**Acceptance:** focused non-PG evaluation/GraphQL tests; each evaluation PG file serially on a proven migrated disposable DB; positive-only finalization; server custom lint.

**Commit:** `feat(server): expose evaluation impact review details`

### Rollout gate A — Server-first push and live schema proof

1. Confirm only accepted Stage 1 is ahead of `origin/main`; plan/journal/unrelated files unstaged.
2. Push `main` and babysit the main pipeline/deploy to terminal success. It rebuilds the unchanged old client plus additive server.
3. Verify live dev schema exposes all four participant fields and both received ack fields; verify Hasura refresh and an old-client-shaped query.
4. Stop on failure. Do not push a new-schema client before this passes.

### Stage 2 — Client protocol, domain, presenters, localization

**Ownership:** schema/documents, repository/use case/entities, presenters, ARBs, mapping/localization tests only.

Map new fields and exact values; omit nullable reason variables; add presenters/EN/RU; run gen-l10n and client codegen without editing/staging generated files.

**Acceptance:** domain/repository/presenter/l10n tests, generated compile, client custom lint.

**Commit:** `feat(client): map evaluation impact review details`

### Stage 3 — Impact control and capability picker primitives

**Ownership:** new control/picker, `CapabilityChipSet`, relevant TestIds, component tests/goldens only.

Build D1/D2 control, optional slug filter, adaptive picker, and keyboard/semantics/text/theme/constraint/cap/filter coverage.

**Acceptance:** component tests/goldens; architect PNG inspection; UI custom lint.

**Commit:** `feat(client): add direct evaluation impact control`

### Stage 4 — Detail sheet, submitted state, card boundary

**Ownership:** sheet, review screen/cubit/state, obsolete control/entity deletion, sheet/card support and workflow tests.

Refactor D3/D4; remove reason authoring and omit input; implement `isSubmitted` and promotion; implement confirmed card action; migrate required integration helpers.

**Acceptance:** detail/card/lifecycle tests; `rg` proves no in-sheet noBasis/trust/intensity/numeric/reason UI; terminology and client lint.

**Commit:** `feat(client): simplify contribution review sheet`

### Stage 5 — Received UI, privacy docs, version/cache

**Ownership:** received surfaces/tests, remaining E2E, privacy copy/docs, pubspec, tracked web index.

Render exact details; correct privacy docs; finish reveal/profile tests; bump `6.12.0` and cache key.

**Acceptance:** received/profile/lifecycle tests; docs/terminology; version consistency.

**Commit:** `feat(client): reveal private impact review details`

## 8. Plan-wide verification

```bash
(cd packages/tentura_lints && dart test)
./scripts/check-custom-lints.sh packages/client
./scripts/check-custom-lints.sh packages/server
bash scripts/check-user-facing-terminology.sh
bash scripts/check-doc-drift.sh
(cd packages/server && dart test --exclude-tags pg)
# Run each evaluation PG file -j 1 against a proven migrated unique tentura_test_* DB.
(cd packages/client && flutter test)
(cd packages/client && flutter test integration_test/request_lifecycle_review_trust_control_test.dart)
(cd packages/client && flutter test integration_test/request_lifecycle_close_review_test.dart)
(cd packages/client && flutter test integration_test/witness_admission_forward_band_test.dart)
(cd packages/client && dart run tool/verify_web_version_consistency.dart)
```

If integration needs the local stack, check port 8888 first and record truly manual browser gates separately.

Before the second push: inspect `git status`; keep plan/journal/unrelated files unstaged; inspect the accepted commit range; run `rg` for obsolete/numeric copy; confirm client schema matches live server; record requirement evidence in the journal.

## 9. Rollout B and babysitting

Push accepted client commits to `origin/main`, babysit tests/builds/dev deployment to terminal result, then verify deployed version/cache key and read-only smoke checks for both received paths. On failure use a fresh bounded Luna correction stage, independently verify, focused-commit, push, and continue. Do not trigger production or mutate unrelated state.

## 10. Compatibility and risks

- Old clients remain compatible; explicit reason arrays still validate/replace.
- New client cannot run against old schema; server-first gate is mandatory.
- Omitted reasons preserve only compatible legacy data; explicit empty clears.
- Stored trust-worded values will be displayed as contribution impact although rows have no wording/version discriminator. This deliberate semantic reinterpretation cannot be migrated precisely and must be documented.
- Persisted stale acknowledgement tags alone are grandfathered; once removed, they cannot be newly reintroduced.
- Old non-positive acknowledgements remain ignored by finalization and hidden in new received UI.
- `isSubmitted` and causal promotion tests prevent drafts masquerading as complete.
- Measure participant allowed-tag query count in journal; batch only through an existing server port if needed, never by duplicating policy client-side.
- Large-text, keyboard, and expanded-window checks are acceptance gates.

## 11. Architect acceptance protocol

After each executor: read journal; inspect owned diff; independently rerun focused gates; challenge dependency direction, GraphQL compatibility, JWT authorization, transaction scope, draft status, finalization, generated handling, design tokens, and causal tests; request fresh bounded corrections; narrowly stage accepted production/docs/tests; exclude plan, journal, unrelated files; commit and journal the hash.

Intermediate green checks are not final closeout. Keep accepted, pending/manual, and blocked gates explicit until Rollout B succeeds.
