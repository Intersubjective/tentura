# Received Reviews & Trust-Change Visibility — Implementation Plan

**Issue:** [#107 Show received reviews and explain trust changes after request closure](https://github.com/Intersubjective/tentura/issues/107) (P1, parent [#96](https://github.com/Intersubjective/tentura/issues/96), regression note from [#76](https://github.com/Intersubjective/tentura/issues/76))
**Status:** implementation-ready. Product decisions (D1-D6) confirmed by the product owner on 2026-08-07; technical design verified against live source across four review passes. §6.4's mid-window visibility question is resolved by defaulting to the status-quo-preserving option (CTA always visible, row content gated until the window closes) — that default needs no new product sign-off because it preserves today's server behaviour exactly; only the *alternative* (relaxing to mid-window reads) would, and it is out of scope here.
**Skills consulted:** `ui-ux-pro-max`, `flutter-build-responsive-layout`, `clean-architecture`, `material-3-flutter` (see §7 for the design output).
**Revision history:** rev 1 (initial); rev 2 — corrected against live-code review findings (Cursor composer-2.5 pass): `noBasis` repository filter, `AttentionEventType` exhaustive-switch surface, destination-family reuse, D5 entry-point widget branching, `closeAndFinalize`/`AttentionIntentCase` wiring, consumer inventory, profile-sliver load pattern, versioning checklist. Rev 3 — corrected against a second independent live-code pass (Cursor grok-4.5, which also re-verified rev 2's own fixes): presentation-payload allowlist vs. per-direction `presentationKey`, copy-builder vs. inline-copy contradiction, `AttentionDispatchIntent.kind` vs. `presentationKey` card dispatch, required beacon-scoped role facts, corrected `beaconTitle`/status-filter/consumer/branch-count citations, expanded §10 (custom_types.dart, build_client.dart routing allowlist, gql_public DTOs). Rev 4 — corrected against a third independent live-code pass (Opus 5 subagent, re-verifying rev 2/3's own fixes too): §4.2's status filter would have leaked mid-window reviews on the profile screen (`submitted` vs `final_`), missing `schema.graphql`/`attention_policy_test.dart`/`home_tab_branches.dart` compile-and-routing prerequisites, corrected "one caller" claim for `listEvaluationsForEvaluatedUser`, `AttentionExpirySweepCase` cannot source `beaconTitle` on its own, contract JSON's `useCase`-vs-`producer` field shapes, `InputFieldUserId` doesn't exist, pill-lint scope, `ConstrainedBox` vs. `TenturaContentColumn`, lint-check command, l10n key count, and several stale cross-references from earlier revisions' renumbering. Rev 5 — fourth live-code pass, re-verifying rev 4's own fixes (all of `submitted`-vs-`final_`, the `AttentionExpirySweepCase` dependency list, the `attention_policy_test.dart` fixture fallback, the two-array contract shape and every `attention_policy.dart`/`attention_models.dart`/`attention_intent_case.dart` line citation checked out): corrected the `producers[]` cardinality claim (one row per use-case file — both files already have one, so no new rows), the `eventTypes[]` multi-producer `producer` format, the `home_tab_branches.dart` `_browsePathOwners`-vs-branch-registration conflation, the `authorHudActGate` path/lines, an inconsistent `evaluation_repository.dart` filter citation, a §6.4 mockup that still promised mid-window content after rev 3 gated it, the `ReviewCloseSnapshot` already carrying the finalized pairs, `EvaluationParticipantRole`'s fourth value, and the `TenturaTone` enum's file; plus an editorial pass to remove patch-log framing and resolve §9 Q4 to an implementable default.

---

## 0. One-page summary

The feature is **half-built and effectively invisible**. A post-close evaluation summary card already exists (`EvaluationSummaryCard`, server `EvaluationCase.evaluationSummary`) but it aggregates reviews anonymously and only renders once **3 distinct evaluators** have reviewed the same person — which almost never happens in 1-on-1 or small-group requests. Trust-change is not shown anywhere. The HUD's only call-to-action disappears the moment a request closes, so there is no path back to whatever summary might exist. Updates has no event type for "someone reviewed you" or "your trust in someone changed."

This plan replaces the anonymized-aggregate model with a **named, recipient-only** model per explicit product decision, and adds:

1. **Server**: drop the N≥3 suppression; expose per-reviewer named rows to the recipient only; emit two new Updates event types when a review window finalizes (`trustGivenChanged` to the reviewer, `trustReceivedChanged` to the reviewed person), driven by the trust-evidence bin already computed during finalization — no new trust math needed.
2. **Client**: a new "My received reviews" screen reachable from a **persistent entry point** on the beacon detail screen (visible from the moment the review window opens through the closed state, replacing the vanishing HUD CTA); a color-coded, icon-plus-text trust-change card in Updates; a "Reviews from this person" section on other users' profile screens.
3. Keep `No basis` visually and semantically distinct from `Neutral` everywhere the receiver can see it (the server-side mapping already keeps them distinct — see §3.3 — though the current client write UI can no longer produce a `noBasis` row at all; §3.3 has the detail).

No public scores, no leaderboards, no exposed MeritRank internals — all changes are additive to the existing private, per-request evaluation and trust-evidence data model.

---

## 1. Product decisions this plan encodes

Locked in by the product owner during scoping (2026-08-07); listed here so implementers don't re-litigate them:

| # | Decision |
|---|---|
| D1 | Aggregation threshold drops from **N ≥ 3 distinct evaluators** to **N ≥ 1**. Suppression by evaluator count is removed entirely. |
| D2 | Reviews shown to their recipient are **named** (reviewer identity attached), not anonymized — but **visible only to the person they were written about**. No third party, including other beacon participants, can see who-said-what-about-whom. |
| D3 | Profile screens gain a section: reviews **this profile's owner** wrote **about the viewer**, across all shared closed requests. (Not reviews the viewer wrote, not reviews third parties wrote — strictly "what they said about me.") |
| D4 | Updates must carry the event end-to-end: both the reviewer ("you now trust X differently") and the reviewed person ("X now trusts you differently, from request Y") get a card, with color-coded direction (green up / red down), icon **and** text (not color alone), plus a plain-language framing that avoids exposing MeritRank internals — "and their network" is descriptive copy about local trust propagation, not a literal per-node breakdown UI. |
| D5 | The entry point to "my received reviews" is **always available on the beacon screen from the moment the review window opens** (`BeaconStatus.reviewOpen`) **through** `BeaconStatus.closed` — it must not depend on, or disappear with, the author-only HUD action rail. |
| D6 | `No basis` stays distinct from `Neutral` in every receiver-facing surface (already true on the server's `reviewValueToBin` mapping — see §3.3 — this plan must not blur it on read paths). |

---

## 2. Current state (condensed — see prior investigation for full detail)

- `EvaluationCase.evaluationSummary` (`packages/server/lib/domain/use_case/evaluation_case.dart:909-948`, helper `_buildEvaluationSummary:45-92`) suppresses below 3 distinct evaluators (`evaluation_case.dart:70`). Rendered by `EvaluationSummaryCard` (`packages/client/lib/features/evaluation/ui/widget/evaluation_summary_card.dart`) via `BeaconEvaluationHooks`, wired only when `beacon.status == BeaconStatus.closed` (`beacon_people_tab_body.dart:344-349`, `beacon_evaluation_hooks.dart:47,69`).
- `EvaluationSummaryCard` itself violates the design system it lives in: raw `Card`/`EdgeInsets.all(12)`/`Chip` inside `beacon_view` scope, which `no_operational_pill_widgets_in_beacon_view` and `no_raw_edge_insets` are meant to catch (custom lints don't run under plain `flutter analyze`, so this slipped through — see `tentura-lints-cli-caveat` memory).
- The author HUD action rail's gate, `authorHudActGate` (`features/beacon_view/ui/presenter/beacon_hud_author_action.dart:38-49`), returns `false` once `beacon.status == BeaconStatus.closed` (lines 41-47); the only closed-state UI is `ClosedRequestBanner` (`closed_request_banner.dart`), a static message with no CTA.
- Trust is **not** written inside `EvaluationCase.evaluationSubmit`. It is written at review-window finalization by `ReviewFinalizationCase.closeAndFinalize` (`packages/server/lib/domain/use_case/evaluation/review_finalization_case.dart:46-102`), which already computes, per (evaluator, evaluated) pair, the exact `TrustBin` (`reviewValueToBin`, `trust_math.dart:5-12`) and records it via `TrustEvidenceRepositoryPort.record` into the `trust_evidence_event` ledger table (schema: `m0122.dart:83-134`, columns `subject_user_id` = reviewer, `object_user_id` = reviewed, `bin`, `source_type`, `request_id`, indexes on `(subject,object,applied_at)` and `(request_id)`).
- `reviewValueToBin` maps `BeaconEvaluationValue.noBasis (0) → null` (no evidence row at all) and `.zero (3) → TrustBin.noEffect` (a real, recorded "no effect" row) — **this is already the correct distinction for D6**; the read side must not collapse them into one label.
- `NotificationKind` (`packages/server/lib/domain/entity/notification_kind.dart`) has `reviewReady` (review became available to *write*) but nothing for "review completed about me" or "trust changed." Updates events are actually keyed by a separate enum, `AttentionEventType` (`packages/server/lib/domain/attention/attention_models.dart:9-32`, 22 values today) — `docs/contracts/updates-event-contract.json` lists 11 `eventTypes` and 45 `producers`, not just the `reviewOpened`/`mutualConnectionFormed`/`inviteAccepted` trio this plan references elsewhere; no producer emits anything at review-window-close time. `AttentionEventType` is consumed by **exhaustive, no-`default` `switch` expressions** in `attention_policy.dart` (`_suppression`, `_category`, `_accessPolicy`, `_destination`, `_presentationKey`) — adding new values there is a compile-time requirement, not optional polish (see §4.4). A dedicated test, `packages/server/test/architecture/updates_event_coverage_test.dart`, also asserts every non-silent contract `producers` entry names a real `AttentionEventType` with an existing `coveringTest` file (`updates_event_coverage_test.dart:44-84`).
- Client design-system tone system already exists and is exactly what this feature needs: `TenturaTone { neutral, info, good, warn, danger }` (`design_system/tentura_tone.dart:2-8`) resolved by `tenturaToneColor()` (`design_system/components/tentura_status_text.dart:8-14`), consumed by `TenturaStatusText`/`TenturaStatusLine`. `TenturaChangeHighlight` (`tentura_change_highlight.dart`) gives an accessible, reduced-motion-aware "this just changed" emphasis animation for free.

**Net verdict:** not a regression — a feature that was deliberately privacy-conservative (aggregate-only, N≥3) to the point of being unreachable in practice, with no lifecycle entry point and no Updates integration. D1/D2 replace the privacy mechanism (anonymize-by-aggregation) with a stricter but more useful one (name it, but lock the audience to exactly one person).

---

## 3. Data model & privacy model

### 3.1 What already gives us D2 for free

Row-level entitlement already exists: `evaluationSummary`'s data source, `listEvaluationsForEvaluatedUser(beaconId, evaluatedUserId)` (`evaluation_repository_port.dart:76`), is called with `userId` = the JWT subject (`evaluation_case.dart:927`). A user can only ever query rows where they are `evaluatedUserId`. **D2's "visible only to whom it's intended" is already structurally true on the query path** — the only thing standing in the way of showing the reviewer's name is the deliberate stripping of identity in `_buildEvaluationSummary`. So D1+D2 together are mostly a **simplification**: delete the suppression branch, add the reviewer identity to each row, keep the existing per-recipient row scoping — with one snag: the repository implementation of `listEvaluationsForEvaluatedUser` itself filters out `value == BeaconEvaluationValue.noBasis` rows before returning them (`evaluation_repository.dart:233-237`), so today's query silently drops exactly the rows D6 needs to render distinctly. Widening that filter is not a local change: `countDistinctEvaluatorsForEvaluated` calls the same method (`evaluation_repository.dart:243-251`) to derive the N≥3 count. See §4.1 for the fix and the cleanup this implies.

This entitlement check is on the **evaluation value**, not on beacon participation: `evaluationSummary`/`evaluationReceived` never verifies the caller is a participant of `beaconId` at all, only that `evaluatedUserId == jwt.sub` (`evaluation_case.dart:909-930`; contrast `evaluationParticipants`, which does check eligibility, `evaluation_case.dart:553-560`). This is **not** a live issue on today's `evaluationSummary` — `EvaluationSummaryResult` (`domain/entity/gql_public/evaluation_summary_result.dart`) has no `beaconTitle` field at all today, so there's nothing to leak yet. It becomes relevant only because §4.1's new `EvaluationReceivedResult` shape deliberately adds `beaconTitle` — once that lands, a non-participant probing an arbitrary `beaconId` would get zero rows (never evaluated) but could still learn the beacon's title/existence. Low severity; decide during §4.1 implementation whether to add a participant guard or accept it, and test whichever is chosen (§7) — don't ship the new field with an unexamined default.

### 3.2 Trust delta: reuse `reviewValueToBin`, don't re-query the ledger

For a single beacon's received-reviews screen, the trust direction for each received review is a pure function of the value already on the row: `reviewValueToBin(ev.value)`. No join to `trust_evidence_event` is needed there — same source of truth the write path uses, so the UI can never show a delta that disagrees with what was actually applied. The ledger *is* the right source for two other things:

- **Cross-beacon aggregation for profile view** (D3) — see §4.2.
- **Triggering the Updates events** (D4) — see §4.3, hooked exactly where `ReviewFinalizationCase` already computes the bin per pair.

### 3.3 `No basis` (D6)

`BeaconEvaluationValue.noBasis = 0` → `allowsReasonTag(0) == false`, `reviewValueToBin(0) == null`. On read, a row with `value == BeaconEvaluationValue.noBasis` must render as **"No basis to judge"** (a distinct, non-toned state — no arrow, no color, an outline/info icon), never merged into "Neutral" (`value == zero == 3`, which *does* get a `TrustBin.noEffect` and must render as "No significant change" with a neutral tone). The server mapping (`trust_math.dart:5-12`) keeps them distinct, satisfying D6 structurally. **But the write side is stronger than "blurred":** `EvaluationTrustSelection` has no member for `noBasis` at all — `fromEvaluationValue` folds `noBasis || zero → EvaluationTrustSelection.zero` on load, and `evaluationValue` (the getter used to submit) can only ever produce `zero/neg1/neg2/pos1/pos2` (`evaluation_trust_selection.dart:49-56,62-67`). The current picker **cannot write a `noBasis` row at all** — only legacy rows (written before this selection UI existed) still carry that value. The `noBasis` render path on the new receiver-side surfaces therefore serves legacy data only; it must still be built (existing rows need to render correctly), but don't expect to exercise it end-to-end with a freshly-submitted review in manual/E2E testing — seed a legacy-shaped row instead.

### 3.4 New index

`trust_evidence_event` has indexes on `(subject_user_id, object_user_id, applied_at DESC)` and `(request_id)`. The profile-view cross-beacon query (§4.2) filters by `(subject_user_id, object_user_id)` only — **already covered by the pair index**, no new index needed there. No new migration is required for §4.2. (Checked: latest migration is `m0139.dart`; nothing here needs `m0140`.)

---

## 4. Server changes

### 4.1 `EvaluationCase.evaluationSummary` → replace with named per-reviewer rows

File: `packages/server/lib/domain/use_case/evaluation_case.dart`.

- Delete `_buildEvaluationSummary` (lines 45-92) and the `distinctEvaluatorCount < 3` branch.
- New shape, e.g. `EvaluationReceivedResult { beaconId, beaconTitle, windowClosed, rows: [EvaluationReceivedRow] }` where `EvaluationReceivedRow = { reviewerId, reviewerDisplayName, reviewerImageId, reviewerRole, value, tone (derived via `reviewValueToBin`, `null` mapped to a `noBasis` sentinel distinct from `noEffect`), reasonTags, note, occurredAt }`. `reviewerRole` reuses `EvaluationParticipantRole`, which has **four** values, not three — `author(0), committer(1), forwarder(2), formerCommitter(3)` (`domain/evaluation/evaluation_participant_role.dart:2-6`); the client role-label mapping (§6.3) must cover `formerCommitter` too.
- **Drop the `noBasis` filter (§3.1):** `evaluation_repository.dart`'s `listEvaluationsForEvaluatedUser` filters on two conditions before returning rows (lines 233-237): `r.value != BeaconEvaluationValue.noBasis` **and** `BeaconEvaluationRowStatus.countsTowardSummary(r.status)` (`submitted || final_`, i.e. excludes drafts). Drop only the `noBasis` clause — keep the status filter, drafts still shouldn't surface. Keeping `submitted` here does **not** contradict §4.2's stricter `final_`-only rule: this use case only ever exposes rows once `windowClosed == true`, and `closeReviewWindow` promotes every `submitted` row to `final_` in the same transaction that flips the beacon to closed (`evaluation_repository.dart:443-457`), so no `submitted` row can reach a receiver through this path. §4.2's cross-beacon query has no window gate at all, which is why it needs the stricter filter.
  Widening the filter in place is safe for the `evaluationReceived` use case, but this is **not** the method's only caller: `countDistinctEvaluatorsForEvaluated` (`evaluation_repository.dart:243-251`) calls it too, to derive the N≥3 count from the returned rows. Since D1 drops that threshold entirely, delete `countDistinctEvaluatorsForEvaluated` in the same cutover rather than silently changing its behavior — it has its own port declaration (`evaluation_repository_port.dart:81-84`), a mock implementation (`data/repository/mock/evaluation_repository_mock.dart:26`), and two test doubles (`test/domain/use_case/coordination_case_revert_test.dart:54`, `test/domain/evaluation/evaluation_case_test.dart:324`) — remove all of them together, along with its only production call site (`evaluation_case.dart:923`), and update the stale "Non–NO_BASIS evaluations for aggregate summary" doc comment above `listEvaluationsForEvaluatedUser` (`evaluation_repository.dart:220`). Map `value == noBasis` to the `noBasis` sentinel in the use case, not in SQL.
- Keep the "review window not yet closed" gate (`beaconStatus != BeaconStatus.closed` today returns `suppressed: true` — becomes `windowClosed: false`, and the client renders an explicit "not available yet" state per issue's "missing/partial reviews have an explicit state rather than a missing button" acceptance criterion).
- `note` and `reasonTags` are already privacy-scoped to the pair (private beacon-local content per the issue's product constraint) — no new exposure beyond "who wrote it," which D2 explicitly authorizes.
- Rename method to `evaluationReceived` (keep `evaluationSummary` as a thin deprecated alias only if another caller still needs the old shape). **Live consumer is `beacon_people_tab_body.dart:344-349`** via `BeaconEvaluationHooks`'s direct `GetIt.I<EvaluationRepository>().fetchSummary(...)` call (`beacon_evaluation_hooks.dart:54`) — that's the actual UI path to migrate. `EvaluationCubit.loadAll` also calls `fetchSummary` (via the client `EvaluationCase`) when `window.windowComplete` (`evaluation_cubit.dart:69-71`), but nothing in `lib/` currently calls `loadAll()` itself — it appears to be dead/unused code, not a second active surface. Update it if `evaluationReceived`'s shape changes so the cubit still compiles, but don't treat it as a second migration target requiring its own UI work. Grep both server (`evaluationSummary`) and client (`fetchSummary`) before deleting the old field/method.

### 4.2 New port method for cross-beacon (profile) queries

File: `packages/server/lib/domain/port/evaluation_repository_port.dart` — add:

```dart
/// Finalized (non-draft, window-closed) evaluations `evaluatorId` wrote about
/// `evaluatedUserId`, across all closed requests, newest first.
Future<List<CrossBeaconEvaluationRecord>> listFinalizedEvaluationsBetween({
  required String evaluatorId,
  required String evaluatedUserId,
});
```

**Status filter: `final_` only, not "submitted or finalized."** `BeaconEvaluationRowStatus` (`domain/evaluation/beacon_evaluation_row_status.dart:2-15`) defines `draft=0, submitted=1, final_=2, responded=3` (`responded` is documented "reserved," unused today). `submitted` is the *still-editable, window-open* state — `isEditableDuringWindow = draft || submitted` (line 13-14) — while `closeReviewWindow` (`evaluation_repository.dart:443-457`) is exactly what promotes rows `submitted → final_` at window close. Do **not** reuse `countsTowardSummary` here (it accepts `submitted || final_`, line 9-10): unlike §4.1's beacon-scoped path, this query has no window-closed gate in front of it, so `submitted` rows would surface named, still-editable, mid-window reviews on the profile screen (§6.5) — precisely the retaliation-risk surface §6.4 gates behind window-closed. Filter `status == BeaconEvaluationRowStatus.final_` only.

**Return type carries more than `BeaconEvaluationRecord` has.** That record has no title/closed-at fields (`domain/entity/evaluation/beacon_evaluation_record.dart:15-23`), but this method is joined to `beacon` for exactly that data (§6.5 renders a tappable request title). Declare a new record type (e.g. `CrossBeaconEvaluationRecord`, shown above) rather than reusing `BeaconEvaluationRecord`.

Implement in the Drift repository (find via `grep -rn "listEvaluationsForEvaluatedUser" packages/server/lib/data/repository/`) as a straightforward query against the same evaluation table filtered by `evaluator_id`, `evaluated_user_id`, and `status = final_`, joined to `beacon` for title/closed-at. New use case method `EvaluationCase.evaluationsWrittenAboutMeBy({required String viewerId, required String authorOfReviewsId})` — enforces `evaluatorId == authorOfReviewsId` and returns rows only when `evaluatedUserId == viewerId` (i.e., the JWT subject), satisfying D2's recipient-only rule for the cross-beacon case the same way §4.1 does for the single-beacon case.

This is a fresh query, so there's no legacy `noBasis` filter to inherit — but don't reintroduce it by pattern-matching `listEvaluationsForEvaluatedUser`'s shape; include `noBasis` rows here too and let the use case map them to the `noBasis` sentinel, same as §4.1.

### 4.3 Updates events at review finalization

Files: `packages/server/lib/domain/use_case/evaluation/review_finalization_case.dart`, `packages/server/lib/domain/port/review_finalization_port.dart`, `packages/server/lib/domain/use_case/evaluation_case.dart`, `packages/server/lib/domain/use_case/attention_expiry_sweep_case.dart`, `packages/server/lib/domain/use_case/attention_intent_case.dart`.

`_recordCommitmentEvidence` (lines 68-102) already loops `snapshot.finalizedEvaluations`, computes `bin = reviewValueToBin(ev.value)`, and skips `null` (no-basis) rows before writing evidence — that's the right per-pair data for the two new events. **But do not inject `AttentionIntentCase` into `ReviewFinalizationCase` to build them from inside it.** There is no need: **both** production call sites of `closeAndFinalize` already hold an `AttentionIntentCase` — `EvaluationCase` as `_attentionIntents`, and `AttentionExpirySweepCase` as `_intents` (`attention_expiry_sweep_case.dart:16,22`). `ReviewFinalizationCase` itself only has repositories + the unit-of-work port (`review_finalization_case.dart:28-44`) and would need a `UserRepositoryPort` added just to build display-name copy, duplicating what `AttentionIntentCase` already does internally (`attention_intent_case.dart:451,670`).

Match the existing `reviewOpened`/`requestStatusChanged` pattern instead — build and record intents in the **caller**, after finalization runs, inside the caller's own transaction:

1. Widen the port: `ReviewFinalizationPort.closeAndFinalize` returns `Future<bool>` today (`review_finalization_port.dart:2`). Change it to also return the finalized `(evaluatorId, evaluatedUserId, bin)` triples **and the beacon title**, e.g. `Future<ReviewFinalizationResult { bool didClose, String beaconTitle, List<FinalizedTrustPair> pairs }>`.
   Most of that data already exists and just isn't surfaced: `ReviewCloseSnapshot` (`domain/entity/review_close_snapshot.dart:16-21`) already carries `finalizedEvaluations` — the `(evaluatorId, evaluatedUserId, value)` triples, produced by `closeReviewWindow`'s `RETURNING evaluator_id, evaluated_user_id, value` promotion query (`evaluation_repository.dart:443-466`) — and `_recordCommitmentEvidence` already turns each `value` into a bin. What the snapshot lacks is `beaconTitle`: add that field and populate it from the `beaconRow` `closeReviewWindow` already reads for the status transition (`evaluation_repository.dart:400-405`). Don't add a separate beacon-repository dependency to `AttentionExpirySweepCase` just to fetch it (see point 8). `EvaluationCase.closeNow` doesn't strictly need the title from the return — it already holds the loaded `beacon` locally (`evaluation_case.dart:501`) — but it should use the same field so both call sites build identical role facts.
2. In `EvaluationCase.closeNow` (`evaluation_case.dart:507-514`) and `AttentionExpirySweepCase.runDue` (`attention_expiry_sweep_case.dart:42-49`) — the two call sites — after `closeAndFinalize` returns, build one `AttentionDispatchIntent` per non-`null`-bin pair (decide `noEffect` inclusion per §9 Q1, default suppress) for each of `trustGivenChanged` (recipient: `evaluatorId`) and `trustReceivedChanged` (recipient: `evaluatedUserId`), and `transaction.record(...)` them alongside the existing `requestStatusChanged` intent (both call sites build only `requestStatusChanged` today — `reviewOpened` fires separately at window-open time, `evaluation_case.dart:294-301`; don't imply the two are paired). `closeNow` currently discards `closeAndFinalize`'s `bool` return entirely (`evaluation_case.dart:507-511`); once the return type widens (point 1), gate trust-intent recording on finalization actually having closed/returned pairs, matching the `didClose` discipline `AttentionExpirySweepCase.runDue` already uses (`attention_expiry_sweep_case.dart:46`).
3. Each trust-change event has exactly **one** recipient, so build the `AttentionDispatchIntent` by hand with a single `AttentionRecipientSnapshot` — the same way `mutualConnectionFormed` and `inviteAccepted` do (`attention_intent_case.dart:609-646,716-752`) — **not** via `fromBeaconNotification`/`BeaconNotificationRecipientResolver`, which is a multi-recipient policy resolver keyed on the legacy `NotificationKind` enum with no case for a single named counterpart. Use the existing `AttentionRecipientReason.reviewParticipant` for the recipient reason (see §4.4 — no new recipient-category values needed).
4. Add matching `AttentionIntentCase.trustGivenChanged(...)` / `trustReceivedChanged(...)` builder methods next to `reviewOpened` (`attention_intent_case.dart:371-389`), following the hand-built-intent shape from point 3.
5. `collapseKey`: use a stable per-`(beaconId, evaluatorId, evaluatedUserId)` key via the existing helper — `AttentionCollapseKey.family('trust_given', [beaconId, evaluatorId, evaluatedUserId])` (`attention_models.dart:156-163`). Dedup is `'${recipientId}|attention-v1|$collapseKey'` (`attention_dispatch_repository.dart:90-91`). Do not reuse `AttentionCollapseKey.none(sourceEventKey)` (never collapses — fine for `reviewOpened`'s one-shot-per-window semantics, but would let a retried finalization double-post a trust card). `beacon_notification_batch_aggregator.dart` switches on `NotificationKind` with a `_ =>` fallback (line 65), so it will not break if trust kinds are omitted from it — giving it a specific plural body is optional polish, not a requirement.
6. **Copy is inline, not via the copy builder.** `beacon_notification_copy_builder.dart` is only invoked from `fromBeaconNotification` (`attention_intent_case.dart:670-673`) and switches on `NotificationKind`, not `AttentionEventType` — it has no bearing on hand-built intents. Write `title`/`body` directly in the new builders, the same way `mutualConnectionFormed` and `inviteAccepted` do (`attention_intent_case.dart:626-629,734-735`), using the evaluator/evaluated display name (via `_users.getById(...)`, as at `attention_intent_case.dart:451,670`) and the bin already computed per pair.
7. **`AttentionDispatchIntent.kind` is a required, non-nullable `NotificationKind` field** (`attention_models.dart:219`) even for hand-built intents — it's a separate, decoupled identity from `AttentionEventType`: `mutualConnectionFormed`'s intent already sets `kind: NotificationKind.inviteAccepted` despite being a different event type (`attention_intent_case.dart:625`). Pick an existing `NotificationKind` value for the two new builders (do not add new ones, per §4.4) and document the choice — it only affects legacy outbox/push-channel plumbing, not the Attention/Updates card, which must dispatch on `presentationKey` instead (§6.2, §5.3).
8. **Required `AttentionRecipientRoleFacts` for both builders**, since `trustGivenChanged`/`trustReceivedChanged` default to beacon-scoped (`AttentionEventTypeScope.isBeaconScoped`'s `_ => true` fallback, `attention_models.dart:35-39`) and `AttentionPolicy.project` enforces a non-empty `role.beaconId` plus a beacon-relationship reason for beacon-scoped events (`attention_policy.dart:18-27`; `reviewParticipant`'s `isBeaconRelationship` defaults `true`, satisfying this): set `beaconId`, `canReadBeaconContent: true` (payload only includes `beaconTitle` when this is true, `attention_policy.dart:295-297`), `beaconTitle` (sourced from `ReviewFinalizationResult`, point 1 — `AttentionExpirySweepCase` has no beacon repository of its own: it only holds `_expiryRepository, _reviewFinalization, _intents, _attention`, `attention_expiry_sweep_case.dart:20-23`, and `AttentionExpiryRepositoryPort` exposes only `lockExpiredReviewWindowBeaconIds`), and `targetEntityId` — the counterpart's user id for `trustGivenChanged` (profile destination), the beacon id for `trustReceivedChanged` (received-reviews destination, whose route param is `beaconId`, not a user id).
9. **`sourceEventKey` and `actionUrl` are both required** on `AttentionDispatchIntent` (`attention_models.dart:216,222`) — there's no default. `attention_occurrence.source_event_key` is unique, and reusing a key with different immutable facts throws `StateError` (`attention_dispatch_repository.dart:24-66`), so each pair/direction needs its own, e.g. `'trust_given:${generateId('A')}'` / `'trust_received:${generateId('A')}'`. `actionUrl` is the push/email fallback link (see the pattern at `attention_intent_case.dart:602,630,736`) — specify its shape for both events, including for `trustReceivedChanged`'s new received-reviews path (§4.4) once that route exists.

Batch per-recipient, not per-bin: that already falls out of building one intent per pair in point 2 — no separate aggregation step is needed.

### 4.4 `AttentionEventType` + contract additions

- `packages/server/lib/domain/attention/attention_models.dart` — add `trustGivenChanged`, `trustReceivedChanged` to the `AttentionEventType` enum (lines 9-32). This is the enum Updates events are actually keyed on (§2); `NotificationKind` (`packages/server/lib/domain/entity/notification_kind.dart`) is a separate, older enum used only by the legacy beacon-notification resolver/copy-builder path that §4.3 deliberately avoids for these two events — **no new `NotificationKind` values needed.**
- `packages/server/lib/domain/attention/attention_policy.dart` — these switches on `AttentionEventType` have **no `_ =>` fallback** and must gain a case for both new values or the file will not compile: `_suppression` (line 56, e.g. `AttentionSuppressionClass.standard`), `_category` (line 101, product call — reuse an existing `NotificationCategory` or add one), `_accessPolicy` (line 129, `AttentionAccessPolicy.beaconContent` — these are beacon-scoped), `_destination` (line 168 — see below and §4.3 point 8 for the destination-specific `targetEntityId`), `_presentationKey` (line 259 — see the direction-encoding decision below and in §5.3). `_requiresAction` (line 226, has a `_ => false` fallback) and `_preferenceClass` (line 212, `_ => null` fallback) will still compile without new cases — add them anyway for clarity but they're not a compile requirement. Also compile-required once `AttentionDestinationKind.receivedReviews` is added below: `AttentionDestinationKindWireName.wireName` (`attention_models.dart:122-130`, no fallback).
- **`beaconContent` access policy plus a `profile` destination is a valid combination** — it looks contradictory but isn't, so don't "fix" `trustGivenChanged` to `AttentionAccessPolicy.profile`. `_accessPolicy` only reserves `profile` for the two non-beacon-scoped events (`attention_policy.dart:136-137`), and `_destination` short-circuits on `recipientSafe` alone (`attention_policy.dart:162-166`) — nothing couples the access policy to the destination kind. `beaconContent` is the one that matters here because the payload's `beaconTitle` is gated on `role.canReadBeaconContent`, and both cards show the request title.
- **`_destination` resolves per event type, not by reusing a family name.** Give `trustGivenChanged` `AttentionDestination(kind: AttentionDestinationKind.profile, targetEntityId: <the counterpart's id, i.e. evaluatedUserId>)` — `AttentionDestinationKind.profile` **already exists** and already resolves client-side to the profile route (`destination_map.dart:26`), matching §6.2's "routes to the counterpart's profile" intent exactly. For `trustReceivedChanged`, **do not reuse `AttentionDestinationKind.review`** — it resolves to `kPathReviewContributions` (`destination_map.dart:25`), the *write-a-review* screen, not a received-reviews screen, and no received-reviews route exists yet. Add a new `AttentionDestinationKind.receivedReviews` value (`attention_models.dart:111-119,121-131`, with its own wire name) plus a matching branch in client `destination_map.dart` (its switch is on the wire-name string and ends in `_ => Uri.parse(receipt.actionUrl)`, `destination_map.dart:11-28`, so an unhandled new kind degrades to the raw action URL rather than failing loudly) pointing at the new `ReceivedReviewsScreen` route (§6.3). Net routing contract, matching §6.2: `trustGivenChanged` → profile, `trustReceivedChanged` → received-reviews.
- `docs/contracts/updates-event-contract.json` has **two arrays with different shapes and different cardinality rules** — only one of them needs new entries.
  - **`eventTypes[]` — add two rows.** Entries are `{eventType, producer, recipientCategory, destinationFamily, muteability, coveringTest}`, enforced by exact key-set equality (`test/architecture/updates_event_contract_test.dart:162`). `producer` is a display string, not a path: single-producer events use `"Class.method"` (`"ForwardCase.forward"`), and **multi-producer events use a pipe-joined list** — see `requestStatusChanged`'s `"BeaconCase|CoordinationCase|EvaluationCase|AttentionExpirySweepCase"` (`updates_event_contract_test.dart:89-97`) and `mutualConnectionFormed`'s method-level variant (`:108-116`). Both new events are built from two call sites per §4.3, so use `"EvaluationCase.closeNow|AttentionExpirySweepCase.runDue"`. Set `destinationFamily` per the point above (`profile` / a new `received_reviews` family), `muteability: "standard"`, and one `coveringTest` per row that resolves to a real file under `packages/server/test/` (enforced at `updates_event_contract_test.dart:172-190`) — `packages/server/test/domain/evaluation/evaluation_case_test.dart` is the natural choice, extended with assertions that the intents are actually built.
  - **`producers[]` — no new rows needed.** Entries are `{useCase, eventType, recipientCategory, destinationFamily, muteability, coveringTest}` (or a `silent`/`silentReason` variant) where **`useCase` is a file path**, and the array is keyed **one row per use-case file**: 45 rows, 45 distinct `useCase` values today. Both producing files already have a row — `evaluation_case.dart` (`eventType: "reviewOpened"`) and `attention_expiry_sweep_case.dart` (`eventType: "requestStatusChanged"`) — and neither lists every event its file emits (`evaluation_case.dart` also emits `requestStatusChanged` and has no second row for it). Follow that convention: leave `producers[]` alone. If you do add rows anyway, they would be the first duplicate `useCase` values in the file; the only exactly-once assertion in `updates_event_coverage_test.dart:33-42` is scoped to `coordination_item/`, so nothing would fail — it would just diverge from the established shape. Do check that the existing rows' `coveringTest` values still cover the new intents; they already point at `evaluation_case_test.dart` and `attention_expiry_sweep_case_test.dart`, the two files §7 extends.
  - Both `packages/server/test/architecture/updates_event_contract_test.dart` and its byte-identical client mirror `packages/client/test/architecture/updates_event_contract_test.dart` assert **exact list equality** for `eventTypes[]` against a hardcoded `_expectedEventTypes` (`:24-127`) — both must be updated in the same change, not just the server one. `packages/server/test/architecture/updates_event_coverage_test.dart` separately enforces that each non-silent `producers` `eventType` exists in `AttentionEventType.values` and that its `coveringTest` resolves to a real file.
- **`packages/server/test/domain/attention/attention_policy_test.dart` needs new fixtures or it fails immediately.** It iterates every `eventTypes` row from the contract (`attention_policy_test.dart:18-24`) and calls `_fixtureFor(eventName)`, whose fallback is `_ => throw StateError('No policy fixture for $eventName')` (`:253`) — so the moment the two contract rows exist, this test throws until fixtures for `trustGivenChanged`/`trustReceivedChanged` are added. Reuse the shared `_baseRole` (`:207-214`), which already sets `beaconId: 'beacon-1'` and `canReadBeaconContent: true` — beacon-scoped events throw in `project()` without a beacon id — paired with `AttentionRecipientReason.reviewParticipant`, exactly as the existing `reviewOpened` fixture does (`:241-244`). `_matchesDestination` also ends in `_ => false` (`:282`), so a `'received_reviews'` contract value needs its own branch there too, or the destination assertion silently fails. Note this test carries its own hardcoded presentation-payload allowlist (`:47-60`), a third place to update if the payload-field fallback below is ever taken.
- **No new `recipientCategory` enum values, and no changes to `beacon_notification_recipient_resolver.dart`.** That resolver switches on `NotificationKind`/`NotificationRecipientReason` for the legacy multi-recipient coordination-item path (`beacon_notification_recipient_resolver.dart:37-100+`) and has no bearing on the hand-built, single-recipient intents from §4.3 point 3. Reuse the existing `AttentionRecipientReason.reviewParticipant`.
- **Trust direction should be encoded as distinct `_presentationKey` values** (e.g. `trust_given_changed_up`/`_down`/`_neutral`, mirroring §6.1's tone table), not as a new presentation-payload field. §5.3 has the mechanics and the fallback path — the short reason to prefer per-key: the payload allowlist (`query_attention.dart:139-147`) rejects any key outside `{eventType, actorUserId, beaconId, coordinationItemId, targetEntityId, messageId, beaconTitle}` and is duplicated in two tests, so a new payload key is a four-file change where a new key value is none.

### 4.5 GraphQL API

File: `packages/server/lib/api/controllers/graphql/query/query_evaluation.dart` — mirror the existing `evaluationSummary` field pattern (lines 97-109):

```dart
GraphQLObjectField<dynamic, dynamic> get evaluationReceived => GraphQLObjectField(
  'evaluationReceived',
  gqlTypeEvaluationReceived.nonNullable(),
  arguments: [InputFieldId.field],
  resolve: (_, args) {
    final jwt = getCredentials(args);
    return _evaluationCase.evaluationReceived(
      beaconId: InputFieldId.fromArgsNonNullable(args),
      userId: jwt.sub,
    ).then(evaluationReceivedToGqlMap);
  },
);

GraphQLObjectField<dynamic, dynamic> get evaluationsWrittenAboutMeBy => GraphQLObjectField(
  'evaluationsWrittenAboutMeBy',
  GraphQLListType(gqlTypeEvaluationReceivedRow.nonNullable()),
  arguments: [InputFieldId.field], // the profile owner being viewed
  resolve: (_, args) {
    final jwt = getCredentials(args);
    return _evaluationCase.evaluationsWrittenAboutMeBy(
      viewerId: jwt.sub,
      authorOfReviewsId: InputFieldId.fromArgsNonNullable(args),
    ).then((l) => l.map(evaluationReceivedRowToGqlMap).toList());
  },
);
```

**`InputFieldUserId` does not exist** — `packages/server/lib/api/controllers/graphql/input/` has `input_field_id.dart` and 15 siblings, and `_input_types.dart` only defines `InputFieldBool/String/StringList/Datetime/Int`. Use `InputFieldId` (shown above, generic enough for a user-id argument) unless there's a reason to add a dedicated `input_field_user_id.dart` — if so, list it in §10.

Add both field getters to `all` (line 14-21). New GraphQL types + mappers go in `gql_v2_dto_maps.dart`, `api/controllers/graphql/custom_types.dart` (`gqlTypeEvaluationSummary` is both declared there, around line 643, and registered in the file's `customTypes` list around line 36 — follow both), and wherever else `gqlTypeEvaluationSummary` is referenced (find via `grep -rn gqlTypeEvaluationSummary packages/server/lib/api`), following that exact declaration's shape (field-by-field `GraphQLObjectField` with nullable/non-nullable per current convention).

---

## 5. Client domain/data layer

### 5.1 `features/evaluation`

- `domain/entity/evaluation_summary.dart` → replace/extend with `evaluation_received.dart` (Freezed): `EvaluationReceivedRow { reviewerId, reviewerDisplayName, reviewerImageId, reviewerRole, trustTone (enum: up, down, noChange, noBasis), reasonTags, note, occurredAt }`, plus `EvaluationReceived { beaconId, beaconTitle, windowClosed, rows }`.
- `data/repository/evaluation_repository.dart` — add `evaluationReceived(beaconId)` and `evaluationsWrittenAboutMeBy(authorOfReviewsId)` methods wrapping the new Ferry-generated GraphQL operations (add sibling documents next to the existing source at `features/evaluation/data/gql/evaluation_summary.graphql`; the generated artifacts land in `_g/`). Map trust tone from the server's numeric bin, not the reverse — the domain entity should already carry a `TenturaTone`-agnostic enum (`up/down/noChange/noBasis`); the *UI* layer maps that to `TenturaTone`, keeping domain free of Flutter/design-system imports (clean-architecture rule: domain has no `ui/` or design-system dependency).
- `domain/use_case/evaluation_case.dart` (client) — thin pass-throughs if the cubit needs orchestration across the two calls (beacon-scoped vs profile-scoped); otherwise the cubit can inject the repository directly per the "thin single-repo cubit" rule in the clean-architecture skill.

### 5.2 `features/profile_view`

- New repository method on the existing `profile_view` data layer (pattern-match `profile_shared_beacons_repository.dart`) or a small new `reviews_about_viewer_repository.dart` — calls `evaluationsWrittenAboutMeBy`.
- `ui/bloc/profile_view_cubit.dart` / `profile_view_state.dart` — add a separate, independently-created cubit (mirror `ProfileSharedBeaconsCubit`, which fetches **eagerly in its constructor** via `unawaited(fetch())` — `profile_shared_beacons_cubit.dart:45,65` — not lazily on scroll into view). A `ProfileReviewsAboutMeCubit` created and fetched when the profile screen opens, same lifecycle as the shared-beacons cubit.

### 5.3 `features/updates`

No domain entity changes — `AttentionReceipt` is already generic (`kind`, `presentationKey`, `presentationPayloadJson`, `beaconId`). `beacon_notification_copy_builder.dart` is not an option for these two events: it's only reachable from `fromBeaconNotification` (`attention_intent_case.dart:670-673`), which §4.3 deliberately avoids (hand-built single-recipient intents, matching `mutualConnectionFormed`/`inviteAccepted`). Copy is authored inline in the new `AttentionIntentCase` builders (§4.3 point 6) — the server always sends non-blank `title`/`body`, so the client fallback path is a generic safety net only.

- **Direction via `_presentationKey`, not a new payload field.** §4.4 gives `_presentationKey` a distinct value per direction (e.g. `trust_given_changed_up`/`_down`/`_neutral`) instead of one key per event type. `_presentationKey` (`attention_policy.dart:259-282`) takes only the event type today, so thread the bin through `AttentionRecipientRoleFacts` (or a similar per-call parameter) into `AttentionPolicy.project`, updating the `_presentationKey(eventType)` call at `attention_policy.dart:44` to also pass `role`/the bin. This avoids touching the presentation-payload allowlist at all, and is safe either way: `_presentationPayload` (`attention_policy.dart:284-305`) builds the payload from an explicit value map, so a new role field can never leak into it by accident. Two further touch points a role-facts change needs: the hand-written serializer `_rolePayload` (`attention_dispatch_repository.dart:251-259`), and `migration/m0129.dart:61-63`, which rebuilds `role_facts` on user delete and would silently drop any new field not accounted for there. Only fall back to a payload field (and extend the allowlist at `query_attention.dart:139-147` plus its two test copies, `query_attention_payload_test.dart` and `attention_policy_test.dart:47-60`) if a direction-per-key isn't workable in practice — don't default to inventing a new payload key.
- `updates_receipt_display_copy.dart` — add the new `_presentationKey` values (per direction) to `_fallbackTitle`/`_fallbackBody` (lines 52-78/80-105) as the generic safety-net copy described above.
- `updates_receipt_card.dart._iconFor` (line 141-147) — **this switches on the receipt's `kind` string (a `NotificationKind` wire name: `'needsMe'`, `'inviteAccepted'`, …), not `presentationKey`/`AttentionEventType`.** Since `mutualConnectionFormed`'s intent carries `kind: NotificationKind.inviteAccepted` despite being a different event (§4.3 point 7), `kind` cannot distinguish trust-given from trust-received, let alone direction. Do not add cases here. Instead, dispatch the specialized `TrustChangeReceiptCard` (§6.2) by switching on `receipt.presentationKey`, and derive the icon/tone directly from the direction already encoded in the matched `_presentationKey` value — no changes to `_iconFor` or `AttentionReceipt` needed.

---

## 6. Client UI (design output from `ui-ux-pro-max` / `flutter-build-responsive-layout` / `material-3-flutter`)

### 6.1 Design tokens to use (no new tokens needed)

Everything maps onto the **existing** `TenturaTone` system — do not invent new colors:

| Trust direction | `TenturaTone` | Icon | Notes |
|---|---|---|---|
| Up (`good`/`veryGood` bin) | `TenturaTone.good` (`tt.good`, emerald) | `Icons.arrow_upward` (or `trending_up`) | Never color alone — icon + short label text ("Trust increased") per `ux-guidelines.csv` `color-not-only` rule. |
| Down (`bad`/`veryBad` bin) | `TenturaTone.danger` (`tt.danger`, rose) | `Icons.arrow_downward` / `trending_down` | Same. |
| Neutral (`noEffect` bin) | `TenturaTone.neutral` (`tt.textMuted`) | `Icons.remove` (flat dash) | "No significant change." |
| No basis (`value == noBasis`, no bin at all) | **not** `TenturaTone.neutral` — no tone at all | `Icons.help_outline` in `tt.textFaint` | Must read visibly different from Neutral — different icon *and* a distinct label ("No basis to judge"), not just a dimmer version of neutral (D6). |

Reuse `TenturaStatusText`/`TenturaStatusLine` for the compact one-line variant (list rows, Updates card subtitle) and `TenturaChangeHighlight` to give a freshly-arrived trust-change card in Updates a brief (220ms, reduced-motion-aware) highlight ring on first render — satisfies the `ui-ux-pro-max` motion rule (150-300ms, meaningful not decorative) for free, no new animation code.

### 6.2 Updates trust-change card

New widget: `packages/client/lib/features/updates/ui/widget/trust_change_receipt_card.dart` (sibling to `updates_receipt_card.dart`; keep the existing generic card for all other kinds and dispatch to this specialized one only for `trustGivenChanged`/`trustReceivedChanged`, decided in `UpdatesScreen`'s list builder or inside `UpdatesReceiptCard` via a `switch` on `receipt.presentationKey` that returns the specialized subtree — **not** `receipt.kind`, see §5.3).

Layout (mobile-first, per `flutter-build-responsive-layout`):

```
┌──────────────────────────────────────────────┐
│ [↑ green | ↓ red | – gray]  Title text         │  ← leading icon uses tt.good/danger/textMuted,
│                              Body text (2 lines)│    never bare Color(...)
│                              Request: "…title…" │  ← existing _requestTitle() pattern, tappable
│                              3h ago             │
└──────────────────────────────────────────────┘
```

- Leading: `Icon` in a tone-colored circular surface (`CircleAvatar`-style using `tt.good.withValues(alpha: 0.12)` background, `tt.good` icon — mirrors how `EvaluationParticipantRole` badges or existing severity chips are built elsewhere; check `tentura_capability_glyph.dart` for the existing "icon in tinted circle" pattern to reuse rather than hand-roll).
- Title always states the **direction in words**, never relies on the arrow alone ("Trust in Alex increased" / "Bota trusts you more now").
- Tapping navigates to the same destination as the generic card (`onTap`), which routes to the "My received reviews" screen (§6.3) scoped to that beacon, or — for `trustGivenChanged` (the reviewer's own outgoing-trust card) — to the counterpart's profile, since there's no "received reviews" screen relevant to what *I* wrote. This falls directly out of the `AttentionDestination` fix in §4.4 — the generic card's `onTap` already resolves through `attentionDestination()`/`destination_map.dart`, so no per-kind special-casing is needed in the card itself once the two destination kinds are correct server-side.
- No horizontal scroll, single column, respects the existing scroll structure in `UpdatesScreen` — a `CustomScrollView` with `SliverList.separated` (`updates_screen.dart:143,156`), not a `ListView` — no new scroll container.
- Desktop/wide layout is already handled: `UpdatesScreen`'s body is wrapped in `TenturaContentColumn` (`updates_screen.dart:86`), the design-system width constraint (`design_system/tentura_responsive_scope.dart`, using `context.tt.contentMaxWidth`). Don't add a redundant `ConstrainedBox(maxWidth: ...)` — the constraint already exists.

### 6.3 "My received reviews" screen

New route/screen: `packages/client/lib/features/evaluation/ui/screen/received_reviews_screen.dart`, `@RoutePage()`, route param `beaconId`. Wire it through a cubit + repository/use-case injection (constructor-injected `EvaluationCase`/`EvaluationRepository`), not `GetIt.I<EvaluationRepository>()` reached for directly inside a widget — `BeaconEvaluationHooks` does that today (`beacon_evaluation_hooks.dart:54`), and it's a clean-architecture smell (widget bypassing the cubit/use-case layer) to not extend onto new screens.

- List of `ReceivedReviewTile` rows (new widget), one per `EvaluationReceivedRow`: avatar (`TenturaAvatar`) + reviewer name + role label (`TenturaTypeLabel`, not `Chip`) + `TenturaStatusText` for the trust direction (tone table in §6.1) + reason tags as plain `TenturaTypeLabel`s (not `Chip`) + note text if present. Note on lint scope: `no_operational_pill_widgets_in_beacon_view` does **not** apply here — it only fires inside `packages/client/lib/features/beacon_view/` (`packages/tentura_lints/lib/src/rules/no_operational_pill_widgets.dart:53-56`), and this screen lives under `features/evaluation/`. `TenturaTypeLabel` over `Chip` is still the right design-system call, just not because of that lint; `no_raw_edge_insets` (scoped to all of `features/**`, `AGENTS.md`) is the lint that actually applies to raw `EdgeInsets` on this screen.
- Empty/partial states (explicit, not a missing button — required by the issue):
  - Window not closed yet → "Reviews will appear here once the request finishes." + link back to the review-window status.
  - Window closed, zero rows → "No one left feedback for you on this request."
  - Row present but `noBasis` → rendered inline per §6.1, not hidden.

Layout (populated state — mobile width, same idea centered under `TenturaContentColumn` above 600px):

```
┌──────────────────────────────────────────────┐
│ ←  My reviews · "Move help this weekend"       │  app bar, back → beacon
├──────────────────────────────────────────────┤
│ (●) Alex K.                    AUTHOR          │  avatar · TenturaTypeLabel
│     ↑ Trust increased                          │  TenturaStatusText, tone=good
│     "Reliable, showed up early."               │  note
│     [reliable]  [on-time]                      │  reason tags, TenturaTypeLabel
│     2 days ago                                 │
│ ─────────────────────────────────────────────  │  TenturaHairlineDivider
│ (●) Mira T.                    COMMITTER        │
│     – No significant change                    │  tone=neutral, dash icon
│     3 days ago                                 │
│ ─────────────────────────────────────────────  │
│ (●) Deni R.                    FORWARDER        │
│     ?  No basis to judge                       │  tone=none, help_outline icon
│     3 days ago                                 │  (visibly distinct from ↑ row)
└──────────────────────────────────────────────┘
```

Empty/partial states (same screen shell, list replaced by a centered message block):

```
Window still open, nobody has reviewed yet:        Window closed, zero eligible reviewers:
┌──────────────────────────────────┐               ┌──────────────────────────────────┐
│               🕐                  │               │               💬                  │
│  Reviews will appear here once    │               │  No one left feedback for you     │
│  the request finishes.            │               │  on this request.                 │
│                                    │               │                                    │
│  [ See review window status ]     │               │  (no button — nothing to do here) │
└──────────────────────────────────┘               └──────────────────────────────────┘
```

- **Responsive** (per `flutter-build-responsive-layout` workflow): wrap the list in `LayoutBuilder`; below 600px, single-column `ListView.builder`; at/above 600px, keep single column but wrap in `TenturaContentColumn` (the design-system width constraint already used by `UpdatesScreen`, §6.2 — not a bespoke `ConstrainedBox`) rather than a raw `maxWidth` constant (a review list is not grid-shaped content — don't force a `GridView` just because there's width to spare; forcing multi-column here would fragment reading order for a fundamentally linear feed, contradicting `content-priority`/`visual-hierarchy` guidance).
- `flutter-build-responsive-layout` explicitly warns against branching on device type or orientation — this screen only branches on `constraints.maxWidth`, never `Theme.of(context).platform` or `MediaQuery.orientationOf`.

### 6.4 Entry points (D5 — always available)

**D5's "always available" is about the entry point, not about unlocking row content early — don't conflate the two.** There is no existing authorization check that would license mid-window reads: `listVisibilityForEvaluator` gates who an evaluator **may write a review about** (checked in `evaluationSubmit`, `evaluation_case.dart:971-979`, and in progress-counting, `evaluation_case.dart:876-888`), and says nothing about who may **read** a submitted review before the window closes — `evaluationReceived`/`evaluationSummary` never consults it (`evaluation_case.dart:909-930`). Showing named, per-reviewer feedback while the window is still open — while other reviewers can still edit their own submissions and the subject can see exactly who said what — would be a new privacy/retaliation-risk surface.

**Implement this default: CTA visible immediately, row content visible only once the window closes.** The entry point (below) is always reachable per D5, but `evaluationReceived` keeps returning `windowClosed: false` with the explicit "reviews appear once the request finishes" state (§6.3) until `beaconStatus == closed` — the same gate `evaluationSummary` applies today (`_buildEvaluationSummary` line 51). This preserves current server behaviour exactly, so it needs no product sign-off to ship.

The alternative, should product later want it, is: rows visible mid-window only for reviewers whose own submission is already locked/finalized for that pair. That requires a real per-pair "is this submission still editable" check, which does not exist today — treat it as a separate, scoped change, not a variant of this one.

Two anchor points, both must render the same CTA (`TenturaCommandButton` or an `OutlinedButton` — check `TenturaCommandButton`'s existing usage for the right variant) that pushes `ReceivedReviewsScreen(beaconId: ...)`. Neither banner is gated by `state.isBeaconMine`: `beacon_operational_header_card.dart` renders `ClosedRequestBanner(beacon: state.beacon)` unconditionally and `ReviewWindowBannerHost(...)` whenever `state.beacon.status == BeaconStatus.reviewOpen` (`beacon_operational_header_card.dart:77,89-93`), and the header card itself is unconditional at its own call site (`beacon_operational_scroll_view.dart:205-208` — only `onAuthorHudAction` is author-gated). `isAuthor: state.isBeaconMine` only steers `ReviewWindowBannerHost`'s *internal* branching, not whether it renders. Both entry points are therefore already reachable by any participant, author or not.

1. **`BeaconStatus.reviewOpen`**: `ReviewWindowBannerHost.build` (`review_window_banner_host.dart:40-106`) has **five** exit paths and only two render substantive banner content — the non-author-with-outstanding-work banner (lines 56-79) and the author-waiting text (lines 81-103). The other three render nothing usable: a loading indicator while `reviewWindowInfo` hasn't loaded yet (lines 42-46), `SizedBox.shrink()` when there's no window or the window is complete (lines 48-50), and `SizedBox.shrink()` again as its final fallback (line 105, covering author-with-`canCloseNow == true` and any other unmatched state). A "secondary always-visible line" cannot simply be appended inside the non-author or the author-waiting branch — it would vanish exactly in the states that fall through to loading or `SizedBox.shrink()`. Restructure so the CTA renders **outside** the widget's internal branching: either (a) change `ReviewWindowBannerHost.build` to always return a `Column` with the CTA as a trailing child appended after whatever the existing branch logic produces (including the two `shrink()` cases — CTA still renders, just with no banner above it), or (b) hoist the CTA out of `ReviewWindowBannerHost` entirely into `beacon_operational_header_card.dart` as a sibling widget rendered whenever `state.beacon.status == BeaconStatus.reviewOpen`, independent of `ReviewWindowBannerHost`'s own render decision. (b) is simpler to reason about since it doesn't require re-deriving which of the five `ReviewWindowBannerHost` states you're in.
2. **`BeaconStatus.closed`**: extend `ClosedRequestBanner` (`closed_request_banner.dart`) — currently a static message with an icon and text only (lines 8-49; its only early return is `beacon.status != BeaconStatus.closed`, so unlike the review-open host this one is safe to patch in place). Add a trailing action button in the same `Row`, same pattern as other HUD action buttons (`beacon_hud_action_button.dart`) — "View my reviews." This directly fixes the "previously available action/button... appeared to be missing" complaint from the issue, since it restores a durable CTA exactly where users expect the old HUD action to have been. Consider hiding the button (not the banner) when the viewer was never evaluated in this beacon, to avoid a CTA that always lands on an empty state for participants who were never review subjects — a UX call, not a hard requirement.

Layout — both banners sit in the same header slot `beacon_operational_header_card.dart` already reserves (`ReviewWindowBannerHost` while `reviewOpen`, `ClosedRequestBanner` while `closed`):

```
reviewOpen (existing ReviewBanner + new always-visible line, per fix above):
┌──────────────────────────────────────────────┐
│ 📝  Review window open · 4 days left            │
│     [ Write your review ]                       │  existing primary CTA, unchanged
│     See the reviews you receive →               │  NEW — always renders, not branch-local;
│                                                 │  lands on the "not available yet" state
│                                                 │  until the window closes (§6.3, §6.4 default)
└──────────────────────────────────────────────┘

closed (existing static banner + new trailing button):
┌──────────────────────────────────────────────┐
│ 🔒  This request is closed.    [ View my reviews → ] │  NEW button in the existing Row
└──────────────────────────────────────────────┘
```

### 6.5 Profile view — "Reviews from this person"

New widget: `packages/client/lib/features/profile_view/ui/widget/reviews_about_me_from_profile_sliver.dart`, pattern-matched directly off `profile_shared_beacons_sliver.dart` (same `SliverList`/`SliverToBoxAdapter` conventions, eager-fetch-on-cubit-create — not lazy-load-on-scroll, see §5.2). The sliver list itself lives in `profile_view_screen.dart` (cubit provided at `:34`, existing shared-beacons sliver at `:80`), not `profile_view_body.dart`.

- Section header: "Reviews from {name}" (only rendered if `rows.isNotEmpty` — omit entirely rather than show an empty-state block on someone else's profile, since a *lack* of reviews from a specific person is not itself informative enough to warrant screen real estate the way "no reviews yet" is on your *own* received-reviews screen).
- Each row: request title (tappable → that beacon, if still accessible) + trust tone + note, same `ReceivedReviewTile`-style rendering as §6.3 (reuse the widget, don't fork it).

Layout — new sliver slotted into the existing `profile_view_screen.dart` sliver list, between the profile header/actions and the pre-existing "shared beacons" sliver (so it reads as "what they've said about you" before "what you've done together"):

```
┌──────────────────────────────────────────────┐
│  (●)  Bota N.                                   │  existing profile header
│       Mutual: 3 connections · [Message] [⋮]     │  existing app bar / actions
├──────────────────────────────────────────────┤
│  Reviews from Bota N.                          │  NEW section — omitted entirely if empty
│                                                 │
│  ↑  "Move help this weekend"                   │  tone icon + tappable request title
│     Trust increased · "fast, careful"          │
│     2 days ago                                 │
│                                                 │
│  ↓  "Errand run downtown"                      │
│     Trust decreased · "missed the window"      │
│     3 weeks ago                                │
├──────────────────────────────────────────────┤
│  Shared requests (3)                           │  existing profile_shared_beacons_sliver
│  ...                                           │
└──────────────────────────────────────────────┘
```

- This section only ever calls `evaluationsWrittenAboutMeBy(profileOwnerId)` — never the reverse — per D3's explicit scope (not "reviews I left about them," which would leak the viewer's own private review content back to them in an unexpected place — actually harmless since it's their own data, but out of scope; don't add it speculatively per the "don't build for hypothetical requirements" project convention).

### 6.6 Fix `EvaluationSummaryCard`'s existing design-system violations

While touching this file (renamed/replaced per §5.1's entity change), also fix the pre-existing lint violations noted in §2: replace `Card`+`EdgeInsets.all(12)` with `tt.cardPadding`/`tt.cardRadius`, replace `Chip` reason-tag rendering with `TenturaTypeLabel`, replace raw `theme.textTheme.*` with `TenturaText.*`. Run `scripts/check-custom-lints.sh packages/client` afterward — `cd packages/tentura_lints && dart test` only runs the rule package's own fixture tests, not the rules against client code; the check script is what actually applies the custom lints to `packages/client` and ratchets against `scripts/custom-lint-baseline.txt` (currently 111 for `packages/client`) — any new violation above that count fails.

### 6.7 l10n

New keys in `packages/client/l10n/app_en.arb` (+ `app_ru.arb`, human-quality Russian, not machine-translated slang — match this repo's existing tone):

```
evaluationReceivedSectionTitle, evaluationReceivedEmptyWindowOpen,
evaluationReceivedEmptyNoReviews, evaluationReceivedNoBasisLabel,
evaluationReceivedNeutralLabel, evaluationReceivedTrustUpLabel,
evaluationReceivedTrustDownLabel, closedRequestViewMyReviewsAction,
reviewWindowViewReceivedReviewsAction, profileReviewsFromPersonSectionTitle,
updatesFallbackTitleTrustGivenChanged, updatesFallbackBodyTrustGivenChanged,
updatesFallbackTitleTrustReceivedChanged, updatesFallbackBodyTrustReceivedChanged
```

Server-composed inline copy (§4.3 point 6, §5.3) reduces how many of these the fallback path actually needs at runtime, but the keys must exist for the safety-net path and for the static screen labels either way. Note §5.3's per-direction `_presentationKey`s mean up to 6 fallback-copy cases (`_up`/`_down`/`_neutral` × given/received) map onto just these 4 `updatesFallback*TrustGivenChanged`/`TrustReceivedChanged` l10n keys — group the `_presentationKey` switch's cases with `||` per direction-agnostic string rather than adding 6 separate l10n keys, or interpolate the direction word into the existing 4 strings.

---

## 7. Testing plan (acceptance criteria → coverage)

| Acceptance criterion | Test |
|---|---|
| Reviewed user finds feedback from both Updates and the closed request | New client widget test on `ReceivedReviewsScreen` (renders rows) + integration test asserting the Updates receipt for `trustReceivedChanged` deep-links to it. |
| UI explains direction/meaning without MeritRank internals | Widget golden test on the trust-change card in all four tone states (up/down/neutral/no-basis) — check no numeric MeritRank score, no "bin"/"edge weight" terminology leaks into copy. |
| Users cannot see raw reviews they're not entitled to | Server test: `evaluationReceived` called with a `userId` that isn't the evaluated user for any row → empty/error, not another user's rows. `evaluationsWrittenAboutMeBy` called with `viewerId != jwt.sub` semantics enforced server-side (never trust a client-supplied "who am I" field) — confirm the resolver derives `viewerId` from the JWT, not an argument. Note: today's `evaluationSummary` has no beacon-participant check (`evaluation_case.dart:909-930`), only the `evaluatedUserId == jwt.sub` row filter — a non-participant probing an arbitrary `beaconId` gets zero rows but still gets back `beaconTitle`; decide whether to add a participant guard or accept the minor existence/title leak, and test whichever is chosen explicitly. |
| Missing/partial reviews have explicit state | Widget test: zero rows + window open → "not available yet" copy; zero rows + window closed → "no feedback" copy; both distinct from a loading/error state. |
| No basis distinct from neutral | Unit test on the tone-mapping function: `value == noBasis` → `noBasisSentinel`, never falls through to `TrustTone.noChange`. **Also** a repository-level regression test asserting `evaluationReceived`'s query actually returns `noBasis` rows (guards against re-introducing the `evaluation_repository.dart:233-237` filter this plan removes — see §4.1). |
| Data persists after reload / across devices | Already true by construction — it's server-sourced, not local-only state; no new test needed beyond the standard repository round-trip test. |
| E2E coverage for author, committer, eligible forwarder | Extend `packages/server/test/domain/evaluation/evaluation_case_test.dart` (note the path: `test/domain/evaluation/`, not `test/domain/use_case/`) and `packages/server/test/domain/use_case/evaluation/review_finalization_case_test.dart` with three-role fixtures (author reviews committer, committer reviews author, forwarder-eligible reviewer) asserting: (a) rows appear in `evaluationReceived` for each pairing, (b) exactly the right `trustGivenChanged`/`trustReceivedChanged` intents fire per pair, (c) no intent fires for `noEffect`/`noBasis` unless the "always send, tone=neutral" decision from §4.3 changes. Also update `packages/client/test/features/evaluation/evaluation_case_test.dart` (has a `fetchSummary` test group and a fake repository that won't compile once `evaluationSummary`'s shape changes). Client integration test via the existing `run_client_integration_web_local.sh` harness — add a scenario closing a request with 1 reviewer (proving D1: the card renders without needing 3 evaluators). |

---

## 8. Rollout order (dependency-ordered phases)

1. **Server data model** (§4.1-4.2): rework `evaluationSummary`→`evaluationReceived`, add cross-beacon port method + repository query. No client change yet — ship behind the existing GraphQL surface being additive (old field can stay until the client cutover, or be removed in the same PR if no other caller exists — check first).
2. **Server events** (§4.3-4.4): widen `closeAndFinalize`'s return, add `trustGivenChanged`/`trustReceivedChanged` builders in `AttentionIntentCase`, record them from `EvaluationCase.closeNow`/`AttentionExpirySweepCase.runDue`, extend `AttentionEventType` + every exhaustive `attention_policy.dart` switch, contract JSON. **No `NotificationKind` additions and no `beacon_notification_recipient_resolver.dart` changes** (§4.3/§4.4). Independently testable via `evaluation_case_test.dart`/`attention_expiry_sweep_case_test.dart` before any client work.
3. **Client evaluation feature** (§5.1, §6.3, §6.4, §6.6): received-reviews screen + entry points + `EvaluationSummaryCard` design-system fix. This alone closes most of the issue's acceptance criteria even before Updates/profile work lands.
4. **Client Updates** (§5.3, §6.2): trust-change receipt card + copy.
5. **Client profile view** (§5.2, §6.5): "Reviews from this person" section — lowest urgency of the four, can slip a sprint without blocking the rest.
6. **l10n + lint/golden cleanup + e2e** (§6.7, §7): last, once copy is stable.

Phases 3 and 4 can run in parallel once phase 2 lands (they depend on the event/contract shape, not on each other). Phase 5 depends only on phase 1.

---

## 9. Open questions for implementers (not product-blocking, but worth a sign-off before coding)

1. **Neutral-bin Updates noise** (§4.3): should a `noEffect` review generate a (muted) Updates card at all, or only up/down reviews? Recommendation: suppress neutral-bin cards to avoid Updates fatigue — a "no change" notification is rarely actionable — but this is a judgment call, not a hard requirement from the issue text.
2. **`trustGivenChanged` destination**: routes to the counterpart's profile rather than a review screen (§6.2/§4.4) — confirm profile routes accept a "scroll to reviews I left" anchor, or just land on the profile top and let the user find it.
3. **Old `evaluationSummary` GraphQL field**: deprecate-in-place vs. hard delete — depends on whether any other client surface still calls it. **Known consumers as of this plan:** `beacon_people_tab_body.dart:344-349` (via `BeaconEvaluationHooks`) and `EvaluationCubit.loadAll` (`evaluation_cubit.dart:69-71`, gated on `window.windowComplete`) — re-verify against the current tree before deleting, since both must migrate together.
4. **Mid-window received-review visibility** (§6.4): **resolved — build the default, don't wait on a sign-off.** "CTA always visible, row content gated until the window closes" keeps today's server gate (`_buildEvaluationSummary` line 51) untouched, so it introduces no new privacy surface and needs no product decision to proceed. The named alternative in §6.4 (mid-window reads for locked pairs) is the one that would need product sign-off *and* new per-pair editability plumbing; it is out of scope here. Flag it to product as an informational note, not a blocker.

---

## 10. File-touch checklist

**Server**
- `domain/use_case/evaluation_case.dart` — rework `evaluationSummary`→`evaluationReceived`, add `evaluationsWrittenAboutMeBy`, build+record `trustGivenChanged`/`trustReceivedChanged` intents in `closeNow` after `closeAndFinalize` (§4.3)
- `domain/use_case/evaluation/review_finalization_case.dart` — widen `_recordCommitmentEvidence`'s per-pair data so it's also returned, not just written as evidence (§4.3) — **no `AttentionIntentCase` injection here**
- `domain/port/review_finalization_port.dart` + implementation — change `closeAndFinalize`'s return type to carry finalized (evaluator, evaluated, bin) pairs and the beacon title
- `domain/entity/review_close_snapshot.dart` — add `beaconTitle` (the pairs are already there as `finalizedEvaluations`); populate it in `closeReviewWindow` from the `beaconRow` it already reads (§4.3 point 1)
- `domain/use_case/attention_expiry_sweep_case.dart` — build+record the same two intents after its own `closeAndFinalize` call (§4.3 point 2)
- `domain/use_case/attention_intent_case.dart` — add `trustGivenChanged(...)`/`trustReceivedChanged(...)` builder methods (hand-built single-recipient intents, pattern-matched off `mutualConnectionFormed`/`inviteAccepted`)
- `domain/attention/attention_models.dart` — add `trustGivenChanged`, `trustReceivedChanged` to `AttentionEventType`; add `AttentionDestinationKind.receivedReviews`
- `domain/attention/attention_policy.dart` — add both event types to every no-fallback switch (`_suppression`, `_category`, `_accessPolicy`, `_destination`, `_presentationKey`, plus `AttentionDestinationKindWireName.wireName` in `attention_models.dart`); `_requiresAction`/`_preferenceClass` cases are optional (have fallbacks)
- `domain/port/evaluation_repository_port.dart` + Drift implementation — `listFinalizedEvaluationsBetween` (status filter `final_` only, §4.2); remove the `noBasis` filter (keep the status filter) from `listEvaluationsForEvaluatedUser`, delete `countDistinctEvaluatorsForEvaluated` and its callers (§3.1/§4.1) — port (`evaluation_repository_port.dart:81-84`), mock (`data/repository/mock/evaluation_repository_mock.dart:26`), test doubles (`test/domain/use_case/coordination_case_revert_test.dart:54`, `test/domain/evaluation/evaluation_case_test.dart:324`)
- `domain/entity/evaluation/` — new `CrossBeaconEvaluationRecord` type for `listFinalizedEvaluationsBetween` (§4.2, `BeaconEvaluationRecord` lacks title/closed-at)
- `domain/entity/gql_public/` — new DTO(s) parallel to `evaluation_summary_result.dart` for `EvaluationReceivedResult`/rows
- `api/controllers/graphql/query/query_evaluation.dart`, `mappers/gql_v2_dto_maps.dart` — new fields/types (use `InputFieldId`, not `InputFieldUserId` — that type doesn't exist, §4.5)
- `api/controllers/graphql/custom_types.dart` — register the new GraphQL object type(s) (`gqlTypeEvaluationSummary`'s declaration and its entry in the `customTypes` list both live here — follow the same pattern for the new type)
- `api/controllers/graphql/query/query_attention.dart` — only if a presentation-payload field is used instead of a per-direction `_presentationKey` (§4.4/§5.3): extend `attentionPresentationPayloadAllowedKeys` + its test
- `data/repository/attention_dispatch_repository.dart` — `_rolePayload` serializer (§5.3) if the bin is threaded through role facts
- `docs/contracts/updates-event-contract.json` — two new `eventTypes` entries only, with the pipe-joined multi-producer `producer` string; `producers[]` needs no new rows (one row per use-case file, and both files already have one) — see §4.4 for the exact field split
- `test/domain/attention/attention_policy_test.dart` — add `_fixtureFor` cases for both new event names (reuse `_baseRole`, which already sets `beaconId`) and a `'received_reviews'` case in `_matchesDestination`, or this test throws the moment the contract gains the two rows (§4.4)
- Tests: `test/domain/evaluation/evaluation_case_test.dart` (correct path, §7), `test/domain/use_case/evaluation/review_finalization_case_test.dart`, `test/domain/use_case/attention_expiry_sweep_case_test.dart`, `test/architecture/updates_event_coverage_test.dart` (contract↔enum↔coveringTest check), `test/architecture/updates_event_contract_test.dart`

**Client**
- `features/evaluation/domain/entity/evaluation_received.dart` (new), retire/adapt `evaluation_summary.dart`
- `features/evaluation/data/repository/evaluation_repository.dart` + new `.graphql` documents
- `data/gql/schema.graphql` — checked-in copy of the server schema; Ferry's codegen input (`build.yaml:32,65`) — add `evaluationReceived`/`evaluationsWrittenAboutMeBy` and their `v2_*` types here first, or `build_runner` fails on the new `.graphql` documents
- `features/evaluation/ui/screen/received_reviews_screen.dart` (new) — via cubit/use-case injection, not `GetIt.I<Repository>()` (§6.3)
- `features/evaluation/ui/widget/evaluation_summary_card.dart` → replace with received-review tile widget(s), design-system compliant
- `features/evaluation/ui/bloc/evaluation_cubit.dart` — migrate off `fetchSummary`/`window.windowComplete` gating (§4.1/§9)
- `features/beacon_view/ui/widget/closed_request_banner.dart` — add CTA (safe in-place patch, single early-return)
- `features/evaluation/ui/widget/review_window_banner_host.dart` **or** `features/beacon_view/ui/widget/beacon_operational_header_card.dart` — add the always-visible CTA outside the widget's existing branch logic (§6.4)
- `features/updates/ui/widget/trust_change_receipt_card.dart` (new)
- `features/updates/updates_receipt_display_copy.dart` — new presentation keys + direction helper
- `features/updates/ui/screen/updates_screen.dart` — dispatch to the specialized card
- `domain/attention/destination_map.dart` — add the `receivedReviews`/`review` distinction (§4.4); `test/domain/attention/destination_map_test.dart` — new wire-name case
- `app/router/root_router.dart` + `consts.dart` — new `ReceivedReviewsRoute`/path const, plus a root `AutoRoute` and a `_forwardIntoHomeBranch` guard mirroring the existing pattern (`root_router.dart:489-505`) so Updates deep-links resolve into it
- `app/router/home_tab_branches.dart` — **two separate edits**: (a) register the branch `AutoRoute` alongside `ReviewContributionsRoute.page`'s (`home_tab_branches.dart:127-131`), and (b) add the new **path const** to `_browsePathOwners` (`:228-238` — that list holds `kPath*` consts such as `kPathReviewContributions`, not route pages), owner `HomeTab.work`. Without (b), tapping the `trustReceivedChanged` Updates card won't resolve into a home-tab branch (`updates_screen.dart:198` → `RootRouter.openFromUpdate` → `homeBranchPathPrefixFor`, which walks this allowlist at `:257-262`)
- `data/service/remote_api_client/build_client.dart` — add the new operation name(s) (e.g. `EvaluationReceived`) to `_tenturaDirectOperationNames` (line ~216, alongside `'EvaluationSummary'`), or the client will misroute the new GraphQL calls
- `features/profile_view/ui/widget/reviews_about_me_from_profile_sliver.dart` (new) slotted into `profile_view_screen.dart` (not `profile_view_body.dart`), `ui/bloc/` new `ProfileReviewsAboutMeCubit` (eager-fetch-on-create, matching `ProfileSharedBeaconsCubit`)
- GraphQL codegen: `.graphql` documents + generated `_g/` files for the two new operations
- `l10n/app_en.arb`, `l10n/app_ru.arb`
- **`pubspec.yaml` version bump** (mandatory for a user-visible client change per `.cursor/rules/versioning.mdc`); check the `MIN_CLIENT_VERSION` decision table in `DEV_GUIDELINES.md` if the gate needs to rise
- Tests: widget/golden tests for the new card + screen states, integration scenario in the web e2e suite, `test/architecture/updates_event_contract_test.dart` (client-side hardcoded `_expectedEventTypes`)
