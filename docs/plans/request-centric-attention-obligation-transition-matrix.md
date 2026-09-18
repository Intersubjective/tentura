# Obligation transition matrix (U07a)

**Repository base:** `d7a220a86` (`feature/events_refac`)  
**Contract:** `docs/contracts/updates-event-contract.json` (`schemaVersion` 4)  
**Scope:** Every `eventClassifications` variant with `attentionClass: obligation` (2 variants).  
**Method:** Trace producers and settlement from live server code only; cite `file:line` or mark **UNVERIFIED**.

Product references: D04, D15, D16 in `docs/plans/request-centric-attention-plan.md`; obligations §5 in `docs/features/request-attention.md`; U03/U03b journal entries for contract shape and known withdrawal gap.

---

## Summary

| Metric | Count |
|---|---|
| Obligation variants in contract | **2** |
| Variants with all contract `resolutionTransitions` implemented | **0** |
| Confirmed settlement gaps (contract transition → **NOT SETTLED**) | **1** (`HelpOfferCase.withdraw` / contract `withdrawHelpOffer`) |
| Contract transition labels with no matching method name in code | **2** (`withdrawHelpOffer`, `submitReviewPackage`) |
| Code settlement paths for `reviewOpened` not listed in contract | **3** (window close, reopen supersede, backfill sweep) |
| Code settlement path for `helpOfferSubmitted` not listed in contract | **1** (user `attentionSettle` / generic Done) |
| Post-expiry optional explanation row (§5) after obligation `expired` | **UNVERIFIED** as shipped — no producer found tied to settlement |

---

## Matrix (one row per obligation variant)

### 1. `helpOfferSubmitted` · `reason:authorOfBeacon`

| Column | Evidence |
|---|---|
| **obligation** | Event `helpOfferSubmitted`; recipient predicate `reason:authorOfBeacon` (`docs/contracts/updates-event-contract.json:485–513`). Runtime obligation when `AttentionRecipientReason.authorOfBeacon` on receipt (`attention_policy.dart:283–285`). |
| **created by** | **Path A — primary help offer:** `HelpOfferCase.offerHelp` → `transaction.record` → `AttentionIntentCase.helpOfferSubmitted` (`help_offer_case.dart:162–170` → `attention_intent_case.dart:64–86`). **Path B — room offer:** `BeaconRoomCase.offerHelp` → `transaction.record` → same intent (`beacon_room_case.dart:970–978` → `attention_intent_case.dart:64–86`). Upsert of an existing active offer does **not** re-emit (`help_offer_case.dart:105–127`). |
| **should end when** (contract `resolutionTransitions`) | `CoordinationCase.acceptHelpOffer` · `CoordinationCase.declineHelpOffer` · `HelpOfferCase.withdrawHelpOffer` (`updates-event-contract.json:509–512`). D04 also names withdrawal and terminal invalidation; only the three contract strings are audited here. |
| **actually settles today** | **`CoordinationCase.acceptHelpOffer`:** `coordination_case.dart:356–360` → `AttentionSystemSettlementPort.settleAuthorHelpOfferSubmitted` → `AttentionSystemSettlementRepository.settleAuthorHelpOfferSubmitted` (`attention_system_settlement_repository.dart:82–112`). **SETTLED.** |
| | **`CoordinationCase.declineHelpOffer`:** `coordination_case.dart:422–426` → same port/repository chain. **SETTLED.** |
| | **`HelpOfferCase.withdrawHelpOffer` (contract label):** Live method is `HelpOfferCase.withdraw` (`help_offer_case.dart:262–330`). Records commitment withdraw, repo withdraw, room access, inbox, optional `helpWithdrawn` attention (`help_offer_case.dart:289–322`). **No** call to `settleAuthorHelpOfferSubmitted` or `AttentionSettlementPort.settle`. **NOT SETTLED.** |
| **expiry path** | No sweeper or beacon-lifecycle hook settles live `helpOfferSubmitted` author obligations. `AttentionExpirySweepCase` only closes review windows (`attention_expiry_sweep_case.dart:27–46`); no help-offer branch. **Nothing** for unanswered author obligations if the helper withdraws or the request moves on without accept/decline. |
| **decline path** | **Domain decline (author rejects offer):** `CoordinationCase.declineHelpOffer` (`coordination_case.dart:366–429`) — exists and settles (see above). Not a “decline obligation” button; author must accept or decline the offer. Obligation CTA is **Respond** (`actionDescriptor: respondToHelpOffer`). |
| **gap** | Withdrawal and any terminal invalidation not covered by accept/decline leave the author obligation live; contract already names withdrawal but code does not settle. Generic user **Done** still settles help-offer obligations outside `resolutionTransitions` (see § Extra settlement paths). |

---

### 2. `reviewOpened` · `reason:reviewParticipant`

| Column | Evidence |
|---|---|
| **obligation** | Event `reviewOpened`; predicate `reason:reviewParticipant` (`updates-event-contract.json:740–767`). Reviewers resolved via `NotificationKind.reviewReady` → `reviewParticipant` (`beacon_notification_recipient_resolver.dart:185–192`). Policy marks `reviewOpened` as requiring action (`attention_policy.dart:286`). |
| **created by** | `EvaluationCase.beaconClose` when opening a review window → `transaction.record` → `AttentionIntentCase.reviewOpened` (`evaluation_case.dart:329–337` inside `beaconClose` from `evaluation_case.dart:163+`). Intent builder: `attention_intent_case.dart:323–341`. |
| **should end when** (contract `resolutionTransitions`) | `EvaluationCase.submitReviewPackage` only (`updates-event-contract.json:764–766`). D04 / §5 also describe window closure, author reopen/cancel, and non-declinable review obligations; those are noted under expiry/decline and § Contract vs code. |
| **actually settles today** | **`EvaluationCase.submitReviewPackage` (contract label):** No method `submitReviewPackage` in `evaluation_case.dart`. Package send is **`EvaluationCase.evaluationFinalize`** (`evaluation_case.dart:1534–1620`). After transactional work, **`settleReviewerObligationOnPackageSend`** (`evaluation_case.dart:1616–1619`) → `AttentionSystemSettlementRepository.settleReviewerObligationOnPackageSend` (`attention_system_settlement_repository.dart:53–79`). **SETTLED** (per reviewer, `settlement_kind = resolved`). Settlement runs **outside** the `runAction` closure (after `evaluation_case.dart:1613`). |
| | **Window close (not in contract list):** `ReviewFinalizationCase.closeAndFinalize` → `settleReviewObligationsAfterWindowClose` (`review_finalization_case.dart:90–91` → `attention_system_settlement_repository.dart:18–50`). Invoked from `EvaluationCase.closeNow` (`evaluation_case.dart:565–570`) and `AttentionExpirySweepCase.runDue` → `closeAndFinalize` (`attention_expiry_sweep_case.dart:43–46`). Sets `resolved` if reviewer status = 2 else `expired`. **SETTLED** (all live `reviewOpened` on beacon). |
| | **Author reopen from review (not in contract list):** `EvaluationCase.reopenFromReview` → `supersedeReviewObligationsOnReopen` (`evaluation_case.dart:474–476` → `attention_system_settlement_repository.dart:115–136`, `settlement_kind = superseded`). **SETTLED.** |
| | **Backfill repair (not in contract list):** `ReviewObligationBackfillCase.run` → `settleReviewObligationsAfterWindowClose` per closed window (`review_obligation_backfill_case.dart:19–26`). **SETTLED** (repair only). |
| **expiry path** | **Timer:** `AttentionExpirySweepCase.runDue` locks expired review windows and calls `ReviewFinalizationCase.closeAndFinalize` with `BeaconLifecycleChangeReason.reviewExpired` (`attention_expiry_sweep_case.dart:27–46`, `review_finalization_case.dart:70–91`). Obligations settle via `settleReviewObligationsAfterWindowClose` (`expired` or `resolved`). **No** follow-up optional “obligation ended” explanation event found in the settlement chain (**UNVERIFIED** for §5 replacement copy — U07b scope). |
| **decline path** | **Forbidden by domain** (§5, D04): no user decline of review obligation. `evaluationSkip` throws (`evaluation_case.dart:1623–1630`). |
| **gap** | Contract omits window-close, reopen-supersede, and backfill transitions though code depends on them. `evaluationFinalize` settlement is outside the attention transaction. No §5 expiry explanation row after `expired` settlement. |

---

## Contract `resolutionTransitions` vs live symbols

| Contract string | Live symbol | Verdict |
|---|---|---|
| `CoordinationCase.acceptHelpOffer` | `acceptHelpOffer` `coordination_case.dart:324` | Exists; settles |
| `CoordinationCase.declineHelpOffer` | `declineHelpOffer` `coordination_case.dart:366` | Exists; settles |
| `HelpOfferCase.withdrawHelpOffer` | **`withdraw`** `help_offer_case.dart:262` only | **Name mismatch**; method exists; **does not settle** |
| `EvaluationCase.submitReviewPackage` | **`evaluationFinalize`** `evaluation_case.dart:1534` | **Name mismatch**; transition exists; settles via `settleReviewerObligationOnPackageSend` |

---

## Extra settlement paths (code settles; contract does not list)

| Target obligation | Entry | Chain | Notes |
|---|---|---|---|
| `helpOfferSubmitted` (author) | GraphQL `attentionSettle` | `mutation_attention.dart:105–110` → `AttentionSettlementCase.settle` (`attention_settlement_case.dart:18–45`) → `AttentionSettlementRepository.settle` (`attention_repository.dart:1298–1331`) | Allowed for live obligations except `reviewOpened` (SQL `occ.event_type IS DISTINCT FROM reviewOpened` at `attention_repository.dart:1322–1328`). **Generic Done** on client: `my_work_obligation_block.dart:147–152` (hidden for review groups `296–304`); `AttentionReceipt.isUserSettleable` excludes `review_opened` (`attention_receipt.dart:78–79`). |
| `reviewOpened` (all reviewers on beacon) | Window close / sweep / author close-now | See matrix row 2 | Not in `resolutionTransitions`. |
| `reviewOpened` | Reopen from review | `evaluation_case.dart:474–476` | `superseded`; not in contract. |
| `reviewOpened` | Backfill job | `review_obligation_backfill_case.dart:24` | Repair; not in contract. |

---

## Review obligations — where user settlement is blocked

| Layer | Location | Behavior |
|---|---|---|
| Use case | `attention_settlement_case.dart:34–39` | Throws if live obligation `eventType == reviewOpened`. |
| Repository | `attention_repository.dart:1322–1328` | `UPDATE` excludes `reviewOpened` rows for any settle kind. |
| Client model | `attention_receipt.dart:78–79` | `isUserSettleable` false when `presentationKey == 'review_opened'`. |
| My Desk UI | `my_work_obligation_block.dart:296–304` | Done control only when `!group.isReview`. |

Review obligations are **not** user-settleable via the public settle mutation; only help-offer obligations are (plus server would reject review anyway).

---

## `staleReminder` and other classified types without live producers

**`staleReminder`:** Confirmed **no** `AttentionEventType.staleReminder` dispatch in `packages/server/lib`. `AttentionIntentCase` has no `staleReminder` builder (grep: only `attention_intent_case.dart` lists other `eventType:` assignments). Contract `producers` points at missing tree `coordination_item/remind_coordination_item_case.dart` (`updates-event-contract.json:321–326`); directory `packages/server/lib/domain/use_case/coordination_item/` **does not exist**. Legacy `NotificationKind.staleRemind` remains in resolver/copy (`beacon_notification_recipient_resolver.dart:208+`) but does not emit Updates attention occurrences. Classification is **optional**, not obligation (`updates-event-contract.json:1035`).

**Other `AttentionEventType` values with intent helpers absent or never called from use cases** (same failure mode as U03b scout; obligation audit does not expand each row):

| Event type | Intent / producer in live `lib/` | Notes |
|---|---|---|
| `needsMe`, `blockerOpened`, `blockerResolved`, `commitmentAccepted`, `commitmentResolved`, `commitmentCancelled`, `commitmentRedirected` | No `eventType:` assignment in any use case; contract producers under missing `coordination_item/*` | **Unemittable** today |
| `staleReminder` | None | **Unemittable** (above) |
| `promiseMade` | `promiseChanged` only in `attention_intent_case.dart:184–208`; **no** `promiseChanged(` call sites in `lib/` (only tests) | **Unemittable** in production paths |

Types that **do** emit via `AttentionIntentCase` + `TransactionalAttentionCase.runAction` include at least: `helpOfferSubmitted`, `reviewOpened`, `relayReceived`, `offerAccepted`/`offerDeclined`/`offerRemoved`, `commitmentReleased`, `coordinationChanged`, `roomMessagePosted`, `requestStatusChanged`, `beaconHierarchyStatusChanged`, `reviewAllPackagesIn`, `reviewWindowCancelled`, trust/deadline/invite/mutual-connection intents (`attention_intent_case.dart` + call sites in `help_offer_case`, `coordination_case`, `evaluation_case`, `beacon_room_case`, `beacon_case`, `deadline_reminder_sweep_case`, etc.).

---

## Gaps ranked (obligation lifecycle impact)

| Rank | Gap | Impact |
|---|---|---|
| **P0** | `HelpOfferCase.withdraw` does not settle author `helpOfferSubmitted` obligation while contract requires it | My desk count stays wrong after withdrawal; violates D04 and U03 contract intent |
| **P1** | Generic `attentionSettle` / Done still resolves help-offer obligations (`attention_settlement_case.dart`, client Done) | Violates D04 / U07b owner decision C; dishonest “resolved” without accept/decline |
| **P1** | D04 “terminal invalidation” (e.g. `offerRemoved`, request close) does not settle author help-offer obligations; not in contract transitions | Obligations can outlive dead offers |
| **P2** | `reviewOpened` contract lists only package send; omits close / supersede / backfill | U07b/U12 reconciliation docs drift from code |
| **P2** | `evaluationFinalize` settlement after transaction boundary (`evaluation_case.dart:1616–1619`) | Rollback / atomicity risk on failure |
| **P3** | No optional explanation attention after `expired` review settlement | §5 trust / “number fell with no story” (U07b) |
| **P3** | Contract method aliases (`withdrawHelpOffer`, `submitReviewPackage`) vs real API names | Traceability only |

---

## Key file index (investigation entry points)

| Area | File |
|---|---|
| User settle | `attention_settlement_case.dart`, `attention_repository.dart` (`AttentionSettlementRepository`), `mutation_attention.dart` |
| System settle | `attention_system_settlement_repository.dart`, `attention_system_settlement_port.dart` |
| Help offer / coordination | `help_offer_case.dart`, `coordination_case.dart` |
| Review | `evaluation_case.dart`, `evaluation/review_finalization_case.dart`, `attention_expiry_sweep_case.dart`, `review_obligation_backfill_case.dart` |
| Dispatch wrapper | `transactional_attention_case.dart`, `attention_intent_case.dart` |
