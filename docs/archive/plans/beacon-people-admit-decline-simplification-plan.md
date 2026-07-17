---
status: done
kind: plan
---
# People tab admit/decline simplification — implementation plan

**Audience:** an LLM/engineer implementing this feature, with no prior context on this conversation.
**Status:** fact-checked against the codebase on 2026-07-09. File/line references are real as of that date — re-verify before editing, code may have moved.
**Scope:** the beacon room "People" tab (committer cards) in `packages/client`, plus the server use cases / data model that back it. No other surface currently renders this control (verified by grep — see §3.8).

---

## 1. Goal, in one paragraph

Today, when an author reviews a committer's help offer, they open a bottom sheet ("Set coordination signal") that mixes a 5-way qualitative signal (useful / overlapping / need-different-skill / need-coordination / not-suitable) with a separate "Admit to chat" checkbox. This is replaced with a **binary decision surfaced directly on the card**: while a commitment is pending, the author sees **Accept** (green, immediately admits to the chat) and **Decline** (opens a popup requiring a reason, shown to the committer). Once someone is admitted — whether by Accept or automatically (e.g. the author forwarded the request directly to them) — the card shows why they're in, and a small, low-emphasis **Remove from chat** affordance lets the author revoke access, using the same reason-popup mechanism as Decline.

---

## 2. Decisions already made — do not re-ask the user these

These were confirmed with the product owner before this doc was written. Implement them as given; do not re-litigate.

1. **Decline reason is mandatory.** The popup's submit control stays disabled until the text field is non-empty.
2. **"Remove from chat" needs no extra confirm step beyond the reason popup itself** — the popup (with its mandatory reason) *is* the confirmation. No secondary "are you sure?" dialog.
3. **Declined/removed committers can be re-admitted later** — this is not a terminal state. See §4.4 for how the plan implements reversal (author can re-decide, not just "committer resubmits").
4. **The label for the revoke action is "Remove from chat"** (not "Revoke access" or similar) — matches user-facing Chat terminology and reads as a social/membership action rather than an administrative one.
5. **The old 5-way `CoordinationResponseType` signal picker is removed from the author-facing UI entirely** — not kept around as a post-admit tracking mechanism. (The enum itself is *not* deleted server-side — see §3.5, it's still load-bearing for evaluation eligibility.)
6. **Auto-admitted committers still get the "Remove from chat" affordance.** Being auto-admitted (e.g. via direct forward) doesn't exempt them from later removal by the author.
7. **"Admitted automatically" needs a new persisted marker.** There is currently no stored distinction between auto-admit and manual-admit (both just set `roomAccess = admitted`). A migration adds this — see §5.
8. **Decline/remove reasons are stored in a new append-only event-log table**, not a single overwritable column, so history survives repeated decline→re-commit→decline cycles. This table is also the source of truth for "how was this person admitted."
9. **The reason is shown to the affected committer via push notification AND persisted on their own view of the card** (not ephemeral-only).
10. **When someone is removed ("kicked"), other admitted participants see a visible system message in the room** ("X was removed from the chat") for transparency — but the *reason* is private between author and the removed committer, never shown in the room-visible system message.

---

## 3. Current state — verified ground truth

### 3.1 The card and its host

- **Card widget:** `packages/client/lib/features/beacon_view/ui/widget/help_offer_tile.dart` — `HelpOfferTile`. Built on `TenturaTechCardStatic`.
- **Host:** `packages/client/lib/features/beacon_view/ui/widget/beacon_people_tab_body.dart` — `BeaconPeopleTabBody`. Renders three accordion sections via `classifyBeaconPeopleSections` (`packages/client/lib/domain/entity/beacon_people_lens.dart:68-149`):
  - `activeHelpers` — author + everyone with `roomAccess == RoomAccessBits.admitted`.
  - `willingToHelp` — non-withdrawn, non-admitted help offers where `coordinationResponse == null` (no author decision yet). **This is "commitments yet to be approved."**
  - `notFitting` — non-withdrawn, non-admitted help offers where `coordinationResponse != null` (author has set some non-admitting response — currently only reachable via the old sheet).
  - `withdrawn` — separate list, unaffected by this feature.

  This bucketing already matches the new binary model almost exactly: pending → `willingToHelp`, admitted (Accept) → `activeHelpers`, declined → `notFitting`. **No changes needed to `classifyBeaconPeopleSections` or `beacon_accordion_sections.dart`** — only to what drives a row between buckets.

### 3.2 Current card controls (`help_offer_tile.dart`)

- Lines 238-258: `isMine` row — `Edit` / `Withdraw` (`TenturaTextAction`), shown to the committer for their own card. Untouched by this feature.
- Lines 216-237 + `_AuthorFooter` (lines 273-334): the coordination footer. Today:
  - If a response exists (`coordinationLabel != null`): shows the author's avatar + `"$coordinationLabel"` text.
  - Else: shows `l10n.helpOffersTabNoAuthorLabelYet` ("no response yet"-style text).
  - If `isAuthorView && onAuthorTapCoordination != null`: shows a `TenturaTextAction` labeled `l10n.labelSetCoordinationResponse` ("Set coordination signal") that opens the sheet. **This whole button is what gets removed.**
- `onAuthorTapCoordination` callback is wired in `beacon_people_tab_body.dart:101-131`, gated on `state.isAuthorOrSteward && !row.isAuthor && beacon.status.isOpenFamily && !c.isWithdrawn && <offer still active>`. This exact gating expression is what future Accept/Decline/Remove callbacks should reuse (it already correctly excludes the author's own row).

### 3.3 The sheet being removed

`packages/client/lib/features/beacon_view/ui/widget/coordination_response_bottom_sheet.dart` — `showCoordinationResponseBottomSheet()` → `_CoordinationSignalSheet`. Single call site is `beacon_people_tab_body.dart:101-131`. Contains:
- A `RadioGroup<CoordinationResponseType>` (5 options).
- A single "Admit to chat" checkbox (`l10n.coordinationInviteToRoomRow`), pre-seeded true for `useful`/`needCoordination`.
- On save, calls back with `(responseTypeSmallint, inviteToRoom, removeFromRoom)` → `BeaconViewCubit.setCoordinationResponse()`.

**Delete this file's usage from `beacon_people_tab_body.dart`.** Whether to delete the file itself is a judgment call — see §9.3.

### 3.4 Data model: what exists today

- **`CoordinationResponseType`** enum (`packages/client/lib/domain/entity/coordination_response_type.dart`, mirrored server-side `packages/server/lib/domain/coordination/coordination_response_type.dart`): `useful(0), overlapping(1), needDifferentSkill(2), needCoordination(3), notSuitable(4)`.
- **`beacon_help_offer_coordination`** table (singular — **not** plural; verify against `grep -rn "beacon_help_offer_coordination" packages/server/lib/data/database/migration/` if this doc is stale). Created in `m0022.dart`, renamed in `m0063.dart`. Schema:
  ```sql
  CREATE TABLE public.beacon_help_offer_coordination (
    offer_beacon_id text NOT NULL,
    offer_user_id text NOT NULL,
    author_user_id text NOT NULL REFERENCES public."user"(id),
    response_type smallint NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (offer_beacon_id, offer_user_id),
    FOREIGN KEY (offer_beacon_id, offer_user_id)
      REFERENCES public.beacon_help_offer (beacon_id, user_id) ON DELETE CASCADE
  );
  ```
  **One mutable row per (beacon, committer)** — every author response overwrites the previous one. No history today.
- **`beacon_participant`** table (Drift-managed query layer; migration-owned schema). Drift table class: `packages/server/lib/data/database/table/beacon_participants.dart`. Relevant column: `roomAccess` (int, `RoomAccessBits`). Registered in `@DriftDatabase(tables: [...])` in `packages/server/lib/data/database/tentura_db.dart:70-87+`.
- **`RoomAccessBits`** (`packages/client/lib/domain/entity/beacon_room_consts.dart:11-18`, mirrored `packages/server/lib/consts/beacon_room_consts.dart`): `none=0, requested=1, invited=2, admitted=3, muted=4, left=5`.

### 3.5 Evaluation coupling — do not break this

`packages/server/lib/domain/evaluation/acknowledged_committer.dart`:
```dart
bool isAcknowledgedCommitterResponse(int? responseType) =>
    responseType == CoordinationResponseType.useful.smallintValue ||
    responseType == CoordinationResponseType.needCoordination.smallintValue;
```
This gates evaluation-participant eligibility (used in `packages/server/lib/domain/use_case/beacon_case.dart:435,485` and `packages/server/lib/domain/use_case/evaluation/evaluation_participant_graph_builder.dart:47`). **`response_type` is not purely a UI concept — it's load-bearing for who counts as "acknowledged" at beacon evaluation time.**

Implication: the new Accept/Decline actions must still write a `response_type` value under the hood:
- **Accept → write `response_type = useful`** (satisfies acknowledgment, correct — the author actively engaged and admitted them).
- **Decline → write `response_type = notSuitable`** (already excluded from acknowledgment — correct, no schema-semantics change needed here).

Do **not** delete the `CoordinationResponseType` enum or the `response_type` column. The `overlapping` / `needDifferentSkill` / `needCoordination` values simply become unreachable from this UI going forward (acceptable — nothing currently reads them for logic other than the acknowledgment check, which only cares about `useful`/`needCoordination`... note `needCoordination` remains a valid "acknowledged" value even though nothing will write it anymore after this change; that's fine, it's dead-but-harmless).

**Known gap, pre-existing, not introduced by this change:** `_autoAdmitIfTrusted()` (§3.6) never writes a `beacon_help_offer_coordination` row at all — an auto-admitted committer currently has no `response_type`, so `isAcknowledgedCommitterResponse` returns false for them (no map entry). Decide during implementation whether auto-admit should now also write `response_type = useful` for consistency (recommended — an auto-admitted, never-removed committer should probably count as acknowledged same as a manually-accepted one) — flagged as an open call in §9.1, not one of the pre-answered decisions in §2.

### 3.6 Admission code paths today

- **Auto-admit** (forward-trust): `packages/server/lib/domain/use_case/help_offer_case.dart:142-174`, `HelpOfferCase._autoAdmitIfTrusted()`. Called from `offerHelp()`. If `_forwardEdgeRepository.isDirectAuthorForward(...)` is true and access wasn't previously explicitly revoked (`existing.roomAccess == RoomAccessBits.none` short-circuits), calls `_beaconRoomRepository.inviteOfferUserToBeaconRoom(...)` (create-if-absent) and `_roomPush.notifyRoomAdmitted(...)`. **Touches only `beacon_participant`, never the coordination table.**
- **Manual admit, currently dead code:** `packages/server/lib/domain/use_case/beacon_room_case.dart:605-631`, `BeaconRoomCase.admit()`. Author/steward-only guard. Calls `_room.admitParticipant(...)` (§3.6.1 — **update-only**, requires an existing `beacon_participant` row). Wired end-to-end but **never called from any client UI today**:
  - GraphQL field: `BeaconRoomAdmit(beaconId, participantUserId): Boolean!` — `packages/server/lib/api/controllers/graphql/mutation/mutation_beacon_room.dart:182-197`.
  - Client operation: `packages/client/lib/features/beacon_room/data/gql/beacon_room_admit.graphql`.
  - Client repository: `packages/client/lib/features/beacon_room/data/repository/beacon_room_repository.dart:489-507` (`admit()`).
  - Client cubit: `packages/client/lib/features/beacon_room/domain/use_case/beacon_room_case.dart:172-175` (`BeaconRoomCase.admit`).
  - **Do not reuse this mutation for the new Accept action** — see §6.4 for why (`Boolean!` return type, wrong owning case class). It's still useful as a reference for the author/steward-guard pattern and the repository call it makes, just not as the field to extend.
- **Manual admit + signal, being retired:** `packages/server/lib/domain/use_case/coordination_case.dart:75-128`, `CoordinationCase.setCoordinationResponse()`. Author-only (see §6.2's authorization note — this looks like a latent bug, since the UI gates on author-or-steward). Upserts `response_type`, then conditionally `revokeOfferUserBeaconRoomAccess` or `inviteOfferUserToBeaconRoom`. Returns `BeaconStatusResult` (also recomputes `beacon.coordination_status` via `_coordinationRepository.beaconStatusSnapshot(beaconId)` — **new mutations must preserve this same return/side-effect contract**, see §6.2 and §6.4).

#### 3.6.1 `admitParticipant` vs `inviteOfferUserToBeaconRoom`

Both in `packages/server/lib/data/repository/beacon_room_repository.dart:779-866`:
- `admitParticipant` (779-797): **update-only** — assumes a `beacon_participant` row already exists. Used by the currently-dead `BeaconRoomCase.admit()`.
- `inviteOfferUserToBeaconRoom` (800-838): **create-if-absent**. Used by auto-admit and the coordination sheet's admit path.

A pending help offer always has a `beacon_participant` row by the time it reaches the "willing to help" bucket (created by whichever "offer help" path ran — see §3.6.2), so `admitParticipant` should be safe for the new Accept action. **Recommend using `inviteOfferUserToBeaconRoom` instead anyway** for defensive robustness (create-if-absent costs nothing and removes a class of edge-case failure) — this is a low-risk deviation from reusing `BeaconRoomCase.admit()` verbatim; note it as a deliberate choice if you take it.

#### 3.6.2 Two parallel "offer help" paths — verify before relying on either

There appear to be **two separate mutations** that both touch help-offer state:
- `HelpOfferCase.offerHelp()` (`help_offer_case.dart:49-140`) — writes `beacon_help_offer` (the offer content/message), calls `_autoAdmitIfTrusted()`.
- `BeaconRoomCase.offerHelp()` → `_room.participantOfferHelp()` (`beacon_room_case.dart:580-589` → `beacon_room_repository.dart:739-777`) — writes/upserts `beacon_participant` (creates with `roomAccess = requested` if absent, **resets to `requested` on every call if the row already existed**, e.g. after a prior removal).

This doc's plan (§4.4) does not depend on resolving this ambiguity — the "Accept/Decline available on any non-admitted row" design sidesteps it entirely. But if you additionally want committer-initiated re-commit (edit-and-resubmit) to *also* reset `coordinationResponse` back to pending, you'll need to trace which of these two paths the client's actual "commit to help" flow calls, and whether it's really both. Don't assume; grep the client call sites (`participantOfferHelp` / `offerHelp` GraphQL operation names) before touching this.

### 3.7 Client-side Clean Architecture layer — do not skip this

The client mirrors the server's layering: **Cubit → domain use-case → repository**, not Cubit → repository directly. Verified in `packages/client/lib/features/beacon_view/domain/use_case/beacon_view_case.dart:174-195` — `BeaconViewCase.setCoordinationResponse()` is what `BeaconViewCubit.setCoordinationResponse()` actually calls (`beacon_view_cubit.dart:371`, `await _case.setCoordinationResponse(...)`), and it does **three things beyond the repository call**:

```dart
Future<({BeaconStatus status, DateTime? updatedAt})> setCoordinationResponse({...}) async {
  final result = await _coordinationRepository.setCoordinationResponse(...);
  _forwardRepository.notifyHelpOfferChanged(HelpOfferInvalidated(beaconId));
  _beaconRoomCase.notifyLocalChange(beaconId: beaconId, entityType: BeaconRoomEntityType.participant);
  await _beaconRepository.refreshAndNotify(beaconId);
  return result;
}
```

These three calls are the client-side local event-bus fan-out that keeps **other screens** (My Work, Inbox) in sync after a mutation the current user just made — this is the exact mechanism documented in this repo's own `docs/plans/beacon-cross-screen-invalidation-refactor.md` (worth reading before touching this). Skipping it doesn't break the People tab itself (which re-fetches directly), but it **will** leave My Work / Inbox cards stale after an accept/decline/remove, reproducing the class of bug that other doc was written to fix.

**Implication for §7:** the new `acceptHelpOffer`/`declineHelpOffer`/`removeFromRoom` methods belong in `BeaconViewCase`, not called directly from the cubit against the repository, and each must replicate this same three-call fan-out (`notifyHelpOfferChanged`, `_beaconRoomCase.notifyLocalChange`, `_beaconRepository.refreshAndNotify`).

### 3.8 Scope confirmation

Grep for other call sites of the coordination sheet, `admit`, `setCoordinationResponse`, and "committer card"-shaped UI found **exactly one surface**: the People tab / `HelpOfferTile`. There is no separate room-member-management screen. **Re-verify this with a fresh grep before implementing**, in case something landed on `main` since this doc was written — the git status at research time showed several in-flight `docs/*.md` files from unrelated work, so the tree is active.

### 3.9 Design-system precedents to reuse

- **Confirm/reason dialog patterns** (pick the reason-input one, not the plain confirm):
  - `packages/client/lib/design_system/components/tentura_confirm_dialog.dart` — `TenturaConfirmDialog` — plain yes/no, no text input. Not what you need here (you need a mandatory text field), but note it for consistency checking.
  - `packages/client/lib/features/inbox/ui/widget/rejection_dialog.dart` — `_InboxNoteDialog` — plain `AlertDialog` + single `TextField(maxLines: 4, maxLength: 200)`, **optional** reason, `Navigator.pop<String>()`. Structurally the closest match, but it's optional and not sheet-adaptive.
  - `packages/client/lib/features/beacon_view/ui/dialog/help_offer_message_dialog.dart` — **best template**. Same feature module as the card you're editing. Uses `showTenturaAdaptiveSheet`, `TenturaSheetDismissGuard`, a `_canSubmit` getter gating the `FilledButton`, `tenturaNoteInputDecoration()` for the text field. Build the new decline/remove-reason dialog as a trimmed-down sibling of this file (single free-text field, no chips, `_canSubmit = _controller.text.trim().isNotEmpty`).
- **Tone/icon system:** `packages/client/lib/design_system/tentura_tone.dart` — `TenturaTone { neutral, info, good, warn, danger }`. `TenturaTextAction` (`packages/client/lib/design_system/components/tentura_text_action.dart`) already supports `tone` + optional `icon`. Existing precedent in the same card: `onWithdraw` uses `TenturaTone.neutral` (`help_offer_tile.dart:254`) — reuse that exact tone for "Remove from chat" (matches the "smaller/gray" request literally).
- **System-message / activity-event mechanism** (for the room-visible "X was removed from chat" message on kick):
  - Server consts: `packages/server/lib/consts/beacon_activity_event_consts.dart` — `BeaconActivityEventTypeBits`, currently `planUpdated=1 ... beaconLifecycleChanged=16`. Visibility: `public=0, room=1` (top of same file).
  - Client mirror: `packages/client/lib/domain/entity/beacon_activity_event_consts.dart`.
  - Client rendering: `packages/client/lib/ui/utils/beacon_activity_event_presenter.dart` — icon/color/label `switch` statements keyed on `BeaconActivityEventTypeBits`. Add a new case here.
  - This is the exact mechanism already used for "Telegram-style inline room messages" (per prior work in this codebase) — reuse it rather than inventing a new system-message concept.
- **Push notification pattern:** `packages/server/lib/data/service/beacon_room_push_service.dart` — one method per `NotificationKind`, e.g. `notifyRoomAdmitted` (lines 50-63). Copy text lives separately in `packages/server/lib/domain/notification/beacon_notification_copy_builder.dart` (hardcoded English strings, e.g. line 58-61: `NotificationKind.roomAccess => ('Chat access', 'You were admitted to the request chat')` — **already terminology-correct**, says "chat"/"request" not "room"/"beacon". Server notification copy is not currently localized (English-only) — follow that existing convention, don't introduce l10n here.

---

## 4. Target UX spec

### 4.1 Card states (author's view, People tab)

| State | Condition | What the author sees |
|---|---|---|
| **Pending** | `roomAccess != admitted`, offer not withdrawn | Two buttons: **Accept** (prominent, `TenturaTone.good`, check icon) and **Decline** (`TenturaTone.danger`, close icon). If a prior decline exists on this same offer, additionally show the previous reason as muted context text above the buttons (e.g. "You previously declined: '{reason}'") so the author isn't re-deciding blind. |
| **Admitted (manual)** | `roomAccess == admitted`, latest admission event `action == accept` | Text: "Admitted". Small `TenturaTone.neutral` **Remove from chat** `TenturaTextAction` alongside it. |
| **Admitted (automatic)** | `roomAccess == admitted`, latest admission event `action == autoAdmit` (or no event row at all — legacy/pre-migration rows, see §9.2) | Text: "Admitted automatically" with a short explanatory subtext, e.g. "— you forwarded this request to them directly". Same **Remove from chat** affordance. |
| **Removed** | `roomAccess != admitted`, latest event `action == remove` | Same Accept/Decline pending controls (removal is reversible — author can Accept again), plus muted context text showing the removal reason they themselves wrote, same treatment as the "previously declined" case above. |

The author never sees their own row (guarded the same way `onAuthorTapCoordination` is guarded today — `!row.isAuthor`).

### 4.2 Card states (committer's own view, `isMine`)

Unaffected: `Edit` / `Withdraw` stay as-is (§3.2). **Add**, in the coordination-footer area:
- If declined: `"Declined: {reason}"` (muted/danger-tinted text, no action).
- If removed: `"Removed from chat: {reason}"` (muted/danger-tinted text, no action).
- If admitted (either kind): the committer doesn't need to know *how* they got in — just show neutral "Admitted" (or nothing extra; the room itself is now visible to them). Don't expose "automatically" framing to the committer — that detail is for the author's benefit (explaining their own past action), not the committer's.
- If pending: keep existing `l10n.helpOffersTabNoAuthorLabelYet`-style "awaiting response" text.

### 4.3 Third-party viewers (neither author nor the committer)

Per `beaconParticipantsVisibleForViewer` (§3.1), most third parties won't even see a non-admitted card. For admitted rows they can see: show plain "Admitted" only — no reason, no automatic/manual distinction, no actions.

### 4.4 Reversal / re-decision model

Per decision §2.3, declines and removals aren't terminal. This plan's mechanism: **Accept/Decline buttons render for any offer where `roomAccess != admitted` and not withdrawn — regardless of whether a prior decline/remove event exists.** This means:
- The author can flip a decline straight to an accept without the committer doing anything.
- The author can flip a "removed" state back to admitted the same way.
- No dependency on the two-offer-paths ambiguity in §3.6.2 — this reversal path works purely through the new mutations described in §6, operating on the existing offer row.

This is a **judgment call**, not one of the pre-confirmed decisions — it's the simplest mechanism that satisfies "not terminal" without touching the committer-resubmission code path. Flag to the product owner if a stricter design (declined offers *require* committer resubmission before the author can act again) turns out to be what was actually wanted.

### 4.5 Copy (proposed — adjust wording freely, but keep something in each slot)

All values go in `.arb` files (both `app_en.arb` and `app_ru.arb` — keys stay `beacon*`/generic, per terminology contract). Suggested keys:

| Key | EN value |
|---|---|
| `helpOfferAdmissionAccept` | "Accept" |
| `helpOfferAdmissionDecline` | "Decline" |
| `helpOfferAdmissionRemove` | "Remove from chat" |
| `helpOfferAdmittedLabel` | "Admitted" |
| `helpOfferAdmittedAutomaticallyLabel` | "Admitted automatically" |
| `helpOfferAdmittedAutomaticallyHint` | "You forwarded this request to them directly" |
| `helpOfferDeclineDialogTitle` | "Decline this offer" |
| `helpOfferDeclineDialogHint` | "Let them know why — this is required" |
| `helpOfferRemoveDialogTitle` | "Remove from chat" |
| `helpOfferRemoveDialogHint` | "Let them know why — this is required" |
| `helpOfferDeclinedWithReason` | "Declined: {reason}" |
| `helpOfferRemovedWithReason` | "Removed from chat: {reason}" |
| `helpOfferPreviousDeclineContext` | "You previously declined: \"{reason}\"" |
| `helpOfferPreviousRemoveContext` | "You previously removed them: \"{reason}\"" |

Remove/leave-unreferenced (decide per §9.3): `labelSetCoordinationResponse`. Keep (still used for the "pending" state text): `helpOffersTabNoAuthorLabelYet`. Existing `coordinationInviteToRoomRow` / `coordinationResponseRoomAdmits` likely become dead once the sheet is deleted — check for other references before removing.

---

## 5. Data model changes

### 5.1 New migration

Next migration number: **`m0113`** (latest today is `m0112` — `grep -c "part 'm0" packages/server/lib/data/database/migration/_migrations.dart` to confirm before writing). Register it the same way `m0112` is registered: add `part 'm0113.dart';` and `m0113,` to the list in `packages/server/lib/data/database/migration/_migrations.dart` (see lines 116-117, 232-233 for the `m0112` pattern).

New file `packages/server/lib/data/database/migration/m0113.dart`, following the exact style of `m0022.dart`/`m0063.dart` (`part of '_migrations.dart';`, `Migration('0113', [ ... raw SQL strings ... ])`):

```sql
CREATE TABLE public.beacon_help_offer_admission_event (
  id text PRIMARY KEY,
  seq bigserial NOT NULL,
  beacon_id text NOT NULL,
  offer_user_id text NOT NULL,
  actor_user_id text NOT NULL REFERENCES public."user"(id),
  action smallint NOT NULL,
  reason text,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT beacon_help_offer_admission_event_offer_fk
    FOREIGN KEY (beacon_id, offer_user_id)
    REFERENCES public.beacon_help_offer (beacon_id, user_id)
    ON DELETE CASCADE,
  CONSTRAINT beacon_help_offer_admission_event_action_check
    CHECK (action BETWEEN 0 AND 3),
  CONSTRAINT beacon_help_offer_admission_event_reason_check
    CHECK (
      (action IN (0, 1) AND reason IS NULL) OR
      (action IN (2, 3) AND reason IS NOT NULL AND length(trim(reason)) BETWEEN 1 AND 500)
    )
);

COMMENT ON TABLE public.beacon_help_offer_admission_event IS
  'Append-only log of admit/decline/remove decisions for a help offer. action: 0=auto_admit,1=accept,2=decline,3=remove. reason is required for decline/remove, null for accept/auto_admit.';

CREATE UNIQUE INDEX beacon_help_offer_admission_event_offer_idx
  ON public.beacon_help_offer_admission_event (beacon_id, offer_user_id, seq DESC);
```

Notes:
- `id` generation: use the existing `generateId(prefix)` convention (see `beacon_room_repository.dart` usages, e.g. `generateId('P')`). As of this writing, prefixes `A, B, C, CE, E, F, I, P, R, S, U, V, X` are taken (`grep -rn "generateId('" packages/server/lib --include="*.dart"` to reconfirm) — pick a free one.
- `actor_user_id`: for `auto_admit` events, set this to the beacon author's id (attributes it consistently — "the author's forward is why this happened").
- **`seq` (bigserial), not `created_at`, is the authoritative "latest event" ordering column.** `created_at` is for display only — two events in the same request can land in the same millisecond, and relying on timestamp ordering alone for "what's the current state" is a race condition waiting to happen. Query the latest row as `ORDER BY seq DESC LIMIT 1` (or a `DISTINCT ON (beacon_id, offer_user_id) ... ORDER BY beacon_id, offer_user_id, seq DESC` window for the whole beacon in one query, matching how `helpOffersWithCoordination` already batches other per-offer lookups — see `coordination_repository.dart`'s `_coordinationByCommitUserId` helper for the existing batching pattern to mirror).
- **The CHECK constraints enforce §2.1's "reason mandatory for decline/remove" decision at the database layer, not just in the dialog's `_canSubmit` gate** — defense in depth against any code path that skips the client-side validation (including future ones).

### 5.2 Drift table class (server query layer)

Per §3.4, this codebase keeps a **hand-written Drift `Table` class in sync manually with the raw-SQL migrations** — Drift is a query-builder layer here, not a schema-authority (confirmed: `packages/server/lib/data/database/table/beacon_participants.dart` mirrors the `beacon_participant` migration SQL by hand). To get `_db.managers.beaconHelpOfferAdmissionEvents`-style type-safe access:

1. Add `packages/server/lib/data/database/table/beacon_help_offer_admission_events.dart`, mirroring `beacon_participants.dart`'s structure (extends `Table`, `late final` columns, explicit `primaryKey`, explicit `tableName`).
2. Register the new table class in the `@DriftDatabase(tables: [...])` list in `packages/server/lib/data/database/tentura_db.dart` (alongside `BeaconParticipants` at line 87).
3. Run `dart run build_runner build -d` inside `packages/server` (per `packages/server/README.md`) to regenerate `tentura_db.g.dart`.

Alternative if you want to avoid the Drift codegen step: use `_db.customInsert`/`customSelect` raw SQL directly in the repository instead of a generated manager. Either is fine; the generated-manager route matches the existing repository's style better (see `admitParticipant` etc. in `beacon_room_repository.dart`), so it's the recommended default.

### 5.3 Realtime invalidation for the new table

Every table that drives client-visible state in this codebase has a matching Postgres trigger firing `pg_notify('entity_changes', ...)` — confirmed precedent: `m0032.dart` added `notify_coordination_change()` + `coordination_entity_notify` trigger specifically because `beacon_help_offer_coordination` (then `beacon_commitment_coordination`) originally had **no** trigger and committers silently missed updates when the author's response changed. Don't reintroduce that exact bug for the new table.

In this plan's design, every write to `beacon_help_offer_admission_event` happens inside the same use-case call as a write to an already-triggered table (`beacon_help_offer_coordination` for accept/decline via `upsertResponse`, `beacon_participant` for remove via `revokeOfferUserBeaconRoomAccess`) — so realtime fan-out is *probably* already covered piggyback. **Don't rely on "probably."**

**If you add an explicit trigger, `entity: 'admission_event'` is not a free choice — verified the client doesn't recognize it.** `packages/client/lib/data/service/invalidation_service.dart`'s `_onInvalidation()` switches on `payload['entity']` with a fixed set of recognized values (`'beacon'`, `'help_offer'`, `'forward'`, `'room_message'`, `'participant'`, etc., `invalidation_service.dart:96+`) — there is no `'admission_event'` case. `pg_notify`-ing with an unrecognized entity name is silently dropped client-side; nothing errors, it just never triggers a refresh. So:
- **(a) Recommended default: reuse `entity: 'help_offer'`.** Zero client-side changes needed — `notify_entity_change()`'s existing `'help_offer'` branch (`m0063.dart`) already fans out to the right users (offerer + beacon author) and the client already refreshes help-offer state on that signal. Add the trigger on the new table using the *existing* `notify_entity_change()` function/branch (or a thin wrapper that resolves `entity_id`/`user_ids` the same way and calls it with `'help_offer'`), not a brand-new entity type.
- **(b) Only if you specifically need a new entity type** (e.g. because "help_offer" refresh semantics don't cover something admission-event-specific): add both the server trigger *and* a new case in `invalidation_service.dart`'s switch, wired to whatever stream/consumer needs it. Don't add one without the other.

Either way, don't skip verifying it works — add a test or a manual QA step that triggers a decline/remove as one user and confirms another connected client (the affected committer, in another session) actually receives a live update, not just a stale state until next poll/navigation.

---

## 6. Server changes

### 6.1 New domain port + entity for admission events

Every existing use case in this codebase depends on **ports** (interfaces), never directly on a Drift table or repository implementation — see `CoordinationCase`'s constructor (`coordination_case.dart:21-35`, injecting `BeaconRepositoryPort`, `HelpOfferRepositoryPort`, `CoordinationRepositoryPort`, `BeaconRoomRepositoryPort`, `EvaluationRepositoryPort`). The admission-event table from §5 needs the same treatment — don't let `CoordinationCase`/`HelpOfferCase` reach into Drift directly.

Add:
- **Domain entity** `packages/server/lib/domain/entity/help_offer_admission_event.dart` (or co-locate near `coordination_response_type.dart`) — a small `HelpOfferAdmissionAction` enum (`autoAdmit(0), accept(1), decline(2), remove(3)`, mirroring `CoordinationResponseType`'s `smallintValue`/`tryFromInt` pattern) plus a `HelpOfferAdmissionEvent` record/class (`beaconId, offerUserId, actorUserId, action, reason, createdAt`).
- **Port** `packages/server/lib/domain/port/help_offer_admission_repository_port.dart` — `HelpOfferAdmissionRepositoryPort` with `Future<void> record({...})` and `Future<HelpOfferAdmissionEvent?> latestFor({required beaconId, required offerUserId})` (plus a batch variant, `latestForBeacon(beaconId)`, for the list query in §7.2 — avoid N+1 the same way `_coordinationByCommitUserId` already batches coordination rows).
- **Implementation** in `packages/server/lib/data/repository/` implementing the port against the Drift table from §5.2, registered in DI the same way other repositories are (`@LazySingleton(as: HelpOfferAdmissionRepositoryPort)` — check an existing repository's annotation for the exact pattern, e.g. how `BeaconRoomPushService` is registered in §3.9's push-service excerpt).
- Inject the new port into **both** `CoordinationCase` (for accept/decline/remove) **and** `HelpOfferCase` (for auto-admit — see below). New constructor parameters mean DI wiring changes; run `dart run build_runner build -d` in `packages/server` after adding, per the codegen note already in §5.2.

### 6.2 New/extended use-case methods

Add to `CoordinationCase` (`packages/server/lib/domain/use_case/coordination_case.dart`) alongside (not replacing) `setCoordinationResponse`:

```
Future<BeaconStatusResult> acceptHelpOffer({beaconId, offerUserId, actorUserId})
Future<BeaconStatusResult> declineHelpOffer({beaconId, offerUserId, actorUserId, required String reason})
Future<BeaconStatusResult> removeFromRoom({beaconId, offerUserId, actorUserId, required String reason})
```

**Authorization — do not copy `setCoordinationResponse`'s guard as-is.** Today's `setCoordinationResponse` calls `_ensureAuthor` (`coordination_case.dart:54-65`, **author-only**, throws for stewards), but the People tab's UI gates the button on `state.isAuthorOrSteward` (`beacon_people_tab_body.dart:104`), and the already-wired `BeaconRoomCase.admit()` correctly checks **author-or-steward** (`beacon_room_case.dart:610-618`). This looks like a latent inconsistency in the existing `setCoordinationResponse` path (worth a note to the team, out of scope to fix here). For the three **new** methods, use `_ensureAuthorOrSteward` (`coordination_case.dart:37-52`) — it matches the UI gate and matches `BeaconRoomCase.admit()`'s precedent. Rename the `authorUserId` param to `actorUserId` throughout (it may not be the author) and thread it through to the admission-event's `actor_user_id` and to the push notification's `actorUserId`.

**Transaction boundary — this is a hard requirement, and it must not leak Drift into the domain layer.** Each of these three methods writes to up to four places (coordination-response upsert, `beacon_participant.roomAccess`, the new admission-event table, and — for remove — a room-visible activity event). Left unwrapped, a mid-sequence failure leaves `roomAccess` and "latest admission event" disagreeing, which directly undermines the event table's role as source-of-truth for the UI (§4.1).

**`_beaconRepository.runInBeaconStateTransaction(...)` is the wrong tool here** — verified its actual signature (`beacon_repository_port.dart:69-74`): it row-locks *one* `beacon` row (`SELECT ... FOR UPDATE`) and hands the caller a locked `BeaconEntity` snapshot; it's built for "read-then-decide-then-write beacon status," not for composing writes across coordination/participant/event tables. Don't reach for it just because it has "transaction" in the name.

The actual proven multi-write-atomicity mechanism in this codebase is **`_database.withMutatingUser(userId, () async {...})`** (`tentura_db.dart:136-147`) — it wraps the callback in a real Drift `transaction()` (not just the GUC-setting it's named for). Confirmed: `CoordinationRepository` and `BeaconRoomRepository` are both constructed with the same `TenturaDb` instance (`coordination_repository.dart:20`, `beacon_room_repository.dart:24`), so calls into either from inside one outer `withMutatingUser` block share the same underlying transaction (Drift nests reentrant `transaction()` calls via savepoints) — this is exactly the pattern `BeaconRepository.recordBeaconStatusTransition` already uses for its own multi-write sequence (`beacon_repository.dart:297-320`, a plain `_database.transaction(() async { two writes })`).

**But the domain use case (`CoordinationCase`) must not call `_database`/Drift directly — that's a Drift-in-domain violation.** So the atomic composition has to live in the **data layer**, exposed to the domain as a single port method per action (not three separate port calls stitched together by the use case, which can't guarantee they share a transaction across different port implementations unless the composition is deliberately built to). Concretely: add `acceptHelpOffer` / `declineHelpOffer` / `removeFromRoom` as methods on **`CoordinationRepositoryPort`** (not scattered across `HelpOfferAdmissionRepositoryPort`, `BeaconRoomRepositoryPort`, and `CoordinationRepositoryPort` separately). The concrete `CoordinationRepository` implementation opens one `_database.withMutatingUser(actorUserId, () async {...})` block and, inside it, performs the coordination-response upsert directly and calls into the room-access and admission-event write logic (either by injecting `BeaconRoomRepository`'s and the new admission repository's *implementations* into `CoordinationRepository`'s constructor — repository-to-repository composition, which is a real but unusual layering choice here — or by having `CoordinationRepository` execute the underlying Drift writes itself, accepting some duplication with `beacon_room_repository.dart`'s `inviteOfferUserToBeaconRoom`/`revokeOfferUserBeaconRoomAccess`). Neither option is clearly "the" existing convention for this exact cross-repository case — pick one, but the constraint that must hold is: **one `withMutatingUser` call, all writes for one admission action inside it, and `CoordinationCase` only ever calls one port method that returns already-committed results.**

Each method's write sequence (all writes below happen inside the single transaction; only the push notification is genuinely post-commit fire-and-forget):

- **`acceptHelpOffer`**: validate offer is active (reuse the existing `_helpOfferRepository.fetchByBeaconId` check, `coordination_case.dart:97-102`) → inside the transaction: upsert coordination response (`responseType: CoordinationResponseType.useful.smallintValue`) → admit to room (§3.6.1 — prefer `inviteOfferUserToBeaconRoom`'s create-if-absent logic over `admitParticipant`) → record admission event (`action: accept, reason: null, actorUserId: actorUserId`) → commit → `unawaited(_roomPush.notifyRoomAdmitted(...))` (reuse existing push — copy already says "admitted to the request chat", still correct).
- **`declineHelpOffer`**: validate `reason.trim().isNotEmpty` server-side (the DB CHECK constraint from §5.1 is the last line of defense, not the first — reject with `HelpOfferCoordinationException(coordinationCode: reasonRequired)`, a new code, see below) → **validate current `roomAccess != admitted`** (if they're already admitted, reject with a new `alreadyAdmitted` code — an admitted committer must go through `removeFromRoom`, not `declineHelpOffer`; without this guard, a direct API call or an out-of-order optimistic-update race could leave `roomAccess = admitted` while the latest event says `decline`, contradicting §4.1's state table) → inside the transaction: upsert response (`notSuitable`) → record admission event (`action: decline`) → **do not touch `roomAccess`** → commit → `unawaited(_roomPush.notifyCommitmentDeclined(...))`.
- **`removeFromRoom`**: validate current `roomAccess == admitted` (else reject with a new `notAdmitted` code — can't remove someone not in the room) → validate `reason.trim().isNotEmpty` (`reasonRequired`) → inside the transaction: revoke room access → **record the admission event AND emit the room-visible activity event (§6.6) here, before commit** — both are part of the atomic write set, not post-commit side effects — → commit → *then* (post-commit, fire-and-forget) `unawaited(_roomPush.notifyCommitmentRemoved(...))`. (An earlier draft of this doc listed the activity event after "transaction commit" in the sequence — that was a mistake; only the push belongs after commit.)

Judgment call, not pre-decided: whether `removeFromRoom` should also reset `response_type` (currently `useful` from a prior accept) back to something else. Recommend **leaving `response_type` as-is** — they were genuinely acknowledged/useful before removal; retroactively erasing that seems wrong for evaluation-eligibility purposes. Flag this choice in the PR description if you go the other way. **But see §7.4 — leaving `response_type = useful` after removal has a concrete client-side consequence (a stale status label) that must be handled, not just noted here.**

**New exception codes.** `HelpOfferCoordinationExceptionCode` (`packages/server/lib/domain/exception_codes.dart:119-128`) currently has no code for these new validation failures — don't overload `invalidResponseType` or `helpOfferNotActive` for them. Add: `reasonRequired`, `reasonTooLong`, `notAdmitted`, `alreadyAdmitted` as new enum values (appended, so existing `codeNumber` values for other codes don't shift — this enum's `codeNumber` is `codeSpace + exceptionCode.index`, so insertion order matters, append-only).

**Reason length bound.** The DB CHECK constraint (§5.1) caps `reason` at 500 trimmed characters (chosen over `_InboxNoteDialog`'s `maxLength: 200` precedent since this reason has more to explain than an inbox dismiss note — adjust the number if you disagree, just keep it consistent everywhere it's checked). Match it in two more places: server-side validation in these three methods (reject over-length input with `reasonTooLong` before it ever reaches the DB — the CHECK constraint should never actually fire in normal operation, it's the backstop) and the client dialog's `TextField(maxLength: 500)` (§7.4/§3.9). This prevents an unbounded string from riding through into the push notification body and the room activity-event-adjacent flows.

**Notification dependency — `CoordinationCase` doesn't have one today.** Verified: `CoordinationCase`'s constructor (`coordination_case.dart:20-27`) injects `BeaconRepositoryPort`, `HelpOfferRepositoryPort`, `CoordinationRepositoryPort`, `BeaconRoomRepositoryPort`, `EvaluationRepositoryPort` — **no `BeaconRoomNotificationPort`**, unlike `HelpOfferCase`, which does have one (`_roomPush`, used for `notifyRoomAdmitted`/`notifyHelpOfferedToModerators`). The pseudocode above assumes `_roomPush` exists on `CoordinationCase` — it doesn't yet. Add `BeaconRoomNotificationPort` as a new constructor parameter on `CoordinationCase` (DI regen required, `dart run build_runner build -d`). See §6.7 for the two new methods that also need adding to the **port interface** (`beacon_room_notification_port.dart`, an `abstract class`), not just its `BeaconRoomPushService` implementation — forgetting the interface method means the concrete class "implements" a method the domain can't call through the port type.

### 6.3 Auto-admit must also record an event

`HelpOfferCase._autoAdmitIfTrusted()` (`help_offer_case.dart:145-174`) is a fixed decision's actual implementation site (§2.7 — "admitted automatically" needs a persisted marker) and **§6.2 above does not cover it** — it's a separate code path from the three new use-case methods. Inject `HelpOfferAdmissionRepositoryPort` into `HelpOfferCase` (§6.1) and add `_admissionRepository.record(action: autoAdmit, reason: null, actorUserId: beacon.author.id)` right after the existing `inviteOfferUserToBeaconRoom` call (line ~162), before the `notifyRoomAdmitted` push. Without this, "Admitted automatically" in the UI never reads a real event — it silently degrades into always hitting the "no event row" legacy fallback from §9.2, which defeats the point of the migration.

### 6.4 GraphQL mutations

**Do not extend `BeaconRoomAdmit`.** It's declared in `MutationBeaconRoom` (`mutation_beacon_room.dart:8` injects `BeaconRoomCase`, not `CoordinationCase`), returns `Boolean!` (`mutation_beacon_room.dart:182-197`), and its dead-but-generated client contract (`beacon_room_repository.dart:489`, `GBeaconRoomAdmitReq`) already assumes that shape. The new `acceptHelpOffer` needs to return `BeaconStatusResult` (same contract as `setCoordinationResponse`, so the beacon's `coordination_status` recomputation stays consistent — §6.2) and lives on `CoordinationCase`, not `BeaconRoomCase`. Reusing the field would mean either breaking its return type (pointless churn on a dead field for no benefit) or awkwardly wrapping a `Boolean!`-returning field to also carry status info. Not worth it — leave `BeaconRoomAdmit` alone (its fate is a separate, out-of-scope cleanup question, §9.3).

Add **three new camelCase fields** in `mutation_coordination.dart` alongside `setCoordinationResponse`, all returning `v2_BeaconStatusResult!` to match its existing convention:

```graphql
acceptHelpOffer(beaconId: String!, offerUserId: String!): v2_BeaconStatusResult!
declineHelpOffer(beaconId: String!, offerUserId: String!, reason: String!): v2_BeaconStatusResult!
removeFromRoom(beaconId: String!, offerUserId: String!, reason: String!): v2_BeaconStatusResult!
```

Each resolves to the matching `CoordinationCase` method from §6.2, with `actorUserId` taken from the JWT (same pattern as `setCoordinationResponse`'s resolver in `mutation_coordination.dart` — check its exact arg-extraction style before writing the new ones). Client-side `.graphql` operation files go under `packages/client/lib/features/beacon_view/data/gql/` (co-locate with the feature that calls them — `beacon_view`, not `beacon_room`; see §7.1).

After adding the schema fields + client operations, regenerate: `dart run build_runner build -d` in **both** `packages/server` and `packages/client` (ferry operation classes, per `packages/client/README.md`). **Then also register each new operation name in `_tenturaDirectOperationNames`** (`packages/client/lib/data/service/remote_api_client/build_client.dart:141+` — confirmed this list already contains `'SetCoordinationResponse'` and `'BeaconRoomAdmit'` as siblings). Codegen alone is not sufficient — without this, the client silently routes the new mutation through Hasura instead of calling the V2 server directly, which will fail since these are V2-only fields, not Hasura-tracked tables. The file's own doc comment (lines 118-130) spells out this exact requirement; it's easy to miss because nothing fails at compile time if you forget it, only at runtime.

### 6.5 Server-side redaction of decline/remove reasons, plus a missing read-access guard

**This is a privacy requirement, not a nice-to-have** — §2.9 says reasons are private to {author/steward, the affected committer}, but nothing in the current query path enforces per-viewer field visibility. Verified: `QueryCoordination.helpOffersWithCoordination` (`query_coordination.dart:19-29`) passes `viewerId: jwt.sub` into `CoordinationCase.helpOffersWithCoordination` → `CoordinationRepository.helpOffersWithCoordination` (`coordination_repository.dart:106-120`), but `viewerId` is used there **only** for `_voteUserFriendshipLookup.reciprocalPositivePeerIds(...)` (an unrelated friendship-reciprocity display concern) — there is no author/steward/self check gating which fields get returned. Combine that with `beaconParticipantsVisibleForViewer`'s "full lens" rule (§3.1 — **any** admitted participant, not just the author, gets full visibility of the row list), and adding a flat `lastDeclineReason`/`lastRemoveReason` field to the row type would leak one committer's private decline reason to every other admitted committer in the room.

**Redaction is authorization policy — it belongs in `CoordinationCase` (the use case), not the repository.** The repository's job is returning data; deciding who's allowed to see which field is a domain/policy concern. Implement it in `CoordinationCase.helpOffersWithCoordination()`, after the repository returns the full rows: compute, per row, whether `viewerId == beacon.author.id || isSteward(viewerId) || viewerId == row.offerUserId`, and null out the reason/admission-detail fields when false, before returning to the resolver. The `admitSource`/"how were they admitted" field is lower-stakes (§4.1 shows it to the author for admitted rows, and it's not sensitive to the committer themselves either) but decide explicitly whether third-party admitted viewers should see it too, or whether it's also author/steward/self-only — recommend the latter for consistency, since §4.3 already says third parties get a bare "Admitted" with no elaboration.

**Separately: `helpOffersWithCoordination` has no read-access guard at all today.** Verified — `CoordinationCase.helpOffersWithCoordination()` (`coordination_case.dart:67-73`) delegates straight to the repository with no `BeaconAccessGuard.canReadContent(beaconId:, viewerId:)` check (the guard `HelpOfferCase` already uses elsewhere, e.g. `help_offer_case.dart:64-68` — `packages/server/lib/domain/port/beacon_access_guard.dart`). This predates this feature and isn't something this plan introduced, but it's a pre-existing gap that gets materially worse once this query starts carrying private decline/remove reasons — anyone who can guess/enumerate a `beaconId` and hold a valid JWT gets the full row list today, reasons included (once added), regardless of whether they can otherwise see the beacon at all. Add `await _guard.canReadContent(beaconId: beaconId, viewerId: viewerId)` at the top of `helpOffersWithCoordination()`, throwing `UnauthorizedException` on false, matching the pattern at `help_offer_case.dart:64-68`. This requires injecting `BeaconAccessGuard` into `CoordinationCase`'s constructor (another new DI dependency, batch it with the `BeaconRoomNotificationPort` addition from §6.2/§6.7 to minimize DI-regen churn).

### 6.6 Room-visible system message on remove

Add a new `BeaconActivityEventTypeBits` value (next free int after `beaconLifecycleChanged = 16`, e.g. `17`, in **both** `packages/server/lib/consts/beacon_activity_event_consts.dart` and the client mirror `packages/client/lib/domain/entity/beacon_activity_event_consts.dart` — keep them numerically identical). Emit it with `visibility = room` from within `removeFromRoom` (§6.2), payload/diff containing just the removed user's id or display name — **not the reason**. Add rendering cases in `packages/client/lib/ui/utils/beacon_activity_event_presenter.dart` — the icon/color switches there use plain Dart values (fine to add a case directly, e.g. icon `Icons.person_remove_outlined`, tone via `beaconActivityLogIconColor`), but the **label** must go through `L10n`, not a hardcoded string — every existing case in `beaconActivityEventLabel()` (`beacon_activity_event_presenter.dart:238-291`) returns an `l10n.beaconActivityXxx` getter; add a matching new `.arb` key (e.g. `beaconActivityParticipantRemoved`) rather than inlining English text, or it'll fail the terminology/l10n contract tests from §8.

Also decide whether the new type counts as a "coordination log" event: `packages/server/lib/consts/beacon_activity_event_consts.dart` has `isCoordinationLogEventType(int type)` (mirrored client-side per its doc comment — "Matches client `BeaconActivityEvent.isCoordinationLogEvent` / Log tab filter"), an explicit allowlist of types shown in whatever "Log" tab/filter consumes that predicate. A membership/room-access change isn't a plan/ask/blocker coordination item — recommend **not** adding the new type to that allowlist (matches how `beaconLifecycleChanged` and other non-coordination types are already excluded), but confirm against the actual Log tab UI behavior before finalizing, since this determines whether removed-participant events show up there too.

### 6.7 Push notifications

**Add the two new methods to both the port interface and its implementation — not just the implementation.** `BeaconRoomPushService` (`beacon_room_push_service.dart`) is a concrete class implementing the abstract `BeaconRoomNotificationPort` (`beacon_room_notification_port.dart`, confirmed `abstract class` with every existing method — `notifyBlockerOpened`, `notifyHelpOfferToAuthor`, etc. — declared there first). `CoordinationCase` will depend on the **port type** (per §6.2's DI note), so declare `notifyCommitmentDeclined`/`notifyCommitmentRemoved` on `BeaconRoomNotificationPort` first, then implement them on `BeaconRoomPushService`, following the exact shape of `notifyRoomAdmitted`/`notifyPlanUpdatedToRoom` (lines 50-63, 95-110) — use `bodyExcerpt: notificationExcerpt(reason)` for the reason text, matching the established pattern for passing free text through pushes:

```dart
Future<void> notifyCommitmentDeclined({required String receiverId, required String beaconId, required String actorUserId, required String reason});
Future<void> notifyCommitmentRemoved({required String receiverId, required String beaconId, required String actorUserId, required String reason});
```

Add corresponding `NotificationKind` values (`packages/server/lib/domain/entity/notification_kind.dart` — currently a flat enum, add e.g. `commitmentDeclined, commitmentRemoved`), then add copy + deep-link routing cases in `packages/server/lib/domain/notification/beacon_notification_copy_builder.dart` (mirror the `roomAccess` case at lines 58-61 for style; **must say "request"/"chat"**, never "beacon"/"room" — this file is one of the explicitly-named terminology-contract locations, see §8). Also check `beacon_notification_batch_aggregator.dart` and `beacon_notification_recipient_resolver.dart` (both showed up in the earlier grep for `NotificationKind` usages) for any exhaustive `switch` that needs a new case added — an unhandled enum value will likely fail to compile or silently drop the notification.

---

## 7. Client changes

### 7.1 New GraphQL operations + generated code

Add `.graphql` operation files under `packages/client/lib/features/beacon_view/data/gql/` for the three mutations exposed in §6.4 (e.g. `beacon_help_offer_accept.graphql`, `beacon_help_offer_decline.graphql`, `beacon_help_offer_remove.graphql`). Also extend the `HelpOffersWithCoordination` query (`packages/client/lib/features/beacon_view/data/gql/help_offers_with_coordination.graphql`) to return the new "current admission state" fields derived server-side from the latest event row (see §5.1), **already redacted per-viewer server-side (§6.5) — the client should never receive a reason it isn't allowed to show** — e.g. `admitSource: Int` (0=auto,1=manual — or reuse the `action` smallint directly), `lastDeclineReason: String`, `lastRemoveReason: String`. Regenerate with `dart run build_runner build -d`, then register the new operation names in `_tenturaDirectOperationNames` (§6.4).

### 7.2 Domain entities

- Extend whatever server resolver backs `HelpOfferWithCoordinationRow` (`packages/server/lib/domain/entity/gql_public/help_offer_with_coordination_row.dart` if that's the right file — verify) to include the new fields from §7.1, sourced from a join against `beacon_help_offer_admission_event` (latest row per offer).
- Extend `TimelineHelpOffer` (client entity backing `HelpOfferTile.helpOffer`) and `BeaconPeopleHelpOfferInput` (`beacon_people_tab_body.dart:52-62`) with the new fields.
- Add a small enum client-side mirroring the `action` smallint (`autoAdmit=0, accept=1, decline=2, remove=3`) if it helps readability — mirrors the `CoordinationResponseType` pattern already in the codebase.

### 7.3 Repository + domain use case + cubit (three layers — see §3.7)

**Do not wire the cubit straight to the repository.** This codebase's client mirrors the server's Clean Architecture: Cubit → domain use case → repository. Verified for the exact method being extended here: `BeaconViewCubit.setCoordinationResponse` (`beacon_view_cubit.dart:371`) calls `_case.setCoordinationResponse` — `BeaconViewCase` (`beacon_view/domain/use_case/beacon_view_case.dart:174-195`), not `CoordinationRepository` directly. Follow the same three-layer shape for all three new actions:

1. **Repository** — `packages/client/lib/features/beacon_view/data/repository/coordination_repository.dart` (today has `setCoordinationResponse`, lines 77-103) — add `acceptHelpOffer`, `declineHelpOffer(reason)`, `removeFromRoom(reason)`, mirroring its existing method shape and the GraphQL request-dispatch pattern used there. Pure data-layer, no side effects beyond the network call.
2. **Domain use case** — `packages/client/lib/features/beacon_view/domain/use_case/beacon_view_case.dart` — add three methods mirroring `setCoordinationResponse` (lines 174-195) **exactly**, including its three-call local-invalidation fan-out (§3.7 — this is the part that's easy to silently drop and would leave My Work/Inbox stale):
   ```dart
   Future<BeaconStatusResult> acceptHelpOffer({required beaconId, required offerUserId}) async {
     final result = await _coordinationRepository.acceptHelpOffer(...);
     _forwardRepository.notifyHelpOfferChanged(HelpOfferInvalidated(beaconId));
     _beaconRoomCase.notifyLocalChange(beaconId: beaconId, entityType: BeaconRoomEntityType.participant);
     await _beaconRepository.refreshAndNotify(beaconId);
     return result;
   }
   ```
   (and the same shape for `declineHelpOffer`/`removeFromRoom`).
3. **Cubit** — `packages/client/lib/features/beacon_view/ui/bloc/beacon_view_cubit.dart` — add three cubit methods mirroring `setCoordinationResponse` (lines 337-384), calling `_case.X(...)` (not the repository):
   - Optimistically patch `state.helpOffers` (set `coordinationResponse`/`roomAccess`) and `state.roomParticipants`, using the existing `patchedHelpOfferRoomAccess` / `applyCoordinationRoomParticipantPatch` helpers as a template (find their definitions near where `setCoordinationResponse` uses them and either reuse or add sibling variants for the new fields).
   - `emit()` the optimistic state.
   - Call `_case.X(...)`; on success `unawaited(_fetchBeaconByIdWithTimeline())`; on failure, re-fetch to roll back and `_showSnackError(e)`, `rethrow`.

### 7.4 Widget changes

**`help_offer_tile.dart`:**
- Delete the `onAuthorTapCoordination` param/callback and the "Set coordination signal" `TenturaTextAction` (lines 324-330).
- Add new callback params: `onAccept`, `onDecline`, `onRemoveFromChat` (all `VoidCallback?`, or `onDecline`/`onRemoveFromChat` might need to trigger the reason dialog themselves — decide whether the dialog opens inside `HelpOfferTile` or in the caller; existing pattern (`onWithdraw` at `beacon_people_tab_body.dart:142-161`) opens the dialog in the **caller**, keeping `HelpOfferTile` itself dumb/presentational — follow that).
- Rewrite `_AuthorFooter` per the state table in §4.1/§4.2: branch on `roomAccess == admitted` first, then on `coordinationResponse`/latest-event fields, per viewer (`isAuthorView` vs `isMine` vs neither). This is the biggest single code change in the client — budget real time for it, and check it against every row of the §4 tables.
- **Also fix the card's status-line header, not just `_AuthorFooter`.** `help_offer_tile.dart:143-149` renders `'${beaconPeopleRoleLabel(...)} · ${beaconPeopleStatusLabel(l10n, participantMeta.status, helpOffer.coordinationResponse)}'` — a *separate* status string from the footer, computed by `beaconPeopleStatusLabel()` (`beacon_people_labels.dart:17-59`). That function special-cases `status == committed && authorResponseForOffered == useful` to return `l10n.beaconPeopleStatusHelpOfferedUseful` (roughly "help offered — useful"). Per §6.2's judgment call, `removeFromRoom` deliberately leaves `response_type = useful` — which means, unmodified, a **removed** committer's card header would still read "useful"-flavored copy, contradicting the "Removed from chat" state shown just below it in the footer. `revokeOfferUserBeaconRoomAccess` (§3.6) only touches `roomAccess`, not `participant.status`, so `status` alone can't disambiguate either. Fix by making `beaconPeopleStatusLabel` (or its call site here) also consider the new latest-admission-event `action` — when it's `remove`, render a "removed" status string instead of falling into the `useful` branch, regardless of what `response_type` still says underneath.
- Reuse `TenturaTextAction` with `tone: TenturaTone.good` + check icon for Accept, `tone: TenturaTone.danger` + close icon for Decline, `tone: TenturaTone.neutral` (matching existing `onWithdraw` styling exactly, line 254) for Remove from chat. Consult the `material-3-flutter` skill before finalizing — this file is inside `features/beacon_view/ui/**`, which is lint-enforced for the design system (no raw `Color(...)`/`TextStyle` literals; use `context.tt` tokens).

**`beacon_people_tab_body.dart`:**
- Replace the `onAuthorTapCoordination` wiring (lines 101-131) with three new callbacks passed into `peopleTile()`'s `HelpOfferTile(...)` construction:
  - `onAccept`: direct cubit call, no dialog, guarded by the same `isAuthorView && !row.isAuthor && beacon.status.isOpenFamily && !c.isWithdrawn` expression as today.
  - `onDecline`: opens the new reason dialog (§7.5), then calls `beaconViewCubit.declineHelpOffer(offerUserId: row.userId, reason: ...)` if not cancelled.
  - `onRemoveFromChat`: same shape as `onDecline` but only shown when `roomAccess == admitted`, calling `removeFromRoom`.

**New file** `packages/client/lib/features/beacon_view/ui/dialog/help_offer_admission_reason_dialog.dart` — trimmed-down sibling of `help_offer_message_dialog.dart` (§3.9): `showTenturaAdaptiveSheet`, single mandatory `TextField(maxLength: 500)` via `tenturaNoteInputDecoration()` (length cap matches §5.1/§6.2's server+DB limit — keep all three in sync), `_canSubmit = _controller.text.trim().isNotEmpty` gating a `FilledButton`, `TenturaSheetDismissGuard` for the dirty-state guard, parameterized `title`/`hint` so it serves both Decline and Remove (per the two dialog-copy rows in §4.5's table).

### 7.5 l10n

Add both `app_en.arb` and `app_ru.arb` entries for every key in §4.5's table (Russian wording: use "запрос"/"чат" per the terminology contract — don't just leave `app_ru.arb` stale, `packages/client/test/l10n/request_terminology_contract_test.dart` will likely catch missing/English-leaked values). Run `bash scripts/check-user-facing-terminology.sh` before considering this done — it regex-scans `.arb` values for forbidden "beacon"/"room" (EN) and "маяк"/"комнат" (RU).

---

## 8. Terminology compliance checklist

Per `.cursor/rules/terminology.mdc` (already fetched in full — see the contract table there). Concretely for this feature:
- [ ] Every new `.arb` value says "request"/"chat" (or Russian equivalents), never "beacon"/"room" as a product noun.
- [ ] Every new server-side user-visible string (push notification titles/bodies in `beacon_notification_copy_builder.dart`, any activity-event label surfaced to the client) follows the same rule — confirmed existing precedent already does this correctly (§3.9).
- [ ] Dart/GraphQL/DB identifiers (`beacon_help_offer_admission_event`, `BeaconRoomAdmit`, `HelpOfferTile`, etc.) **keep saying "beacon"/"room"** — that's correct and required, only user-facing *values* get the alias.
- [ ] Run `bash scripts/check-user-facing-terminology.sh` and `packages/client/test/l10n/request_terminology_contract_test.dart` before calling this done.

---

## 9. Open judgment calls flagged for the implementer

These were **not** put to the product owner (diminishing returns on further grilling) — make a reasonable call, document it in the PR description, and be ready to adjust.

### 9.1 Should auto-admit also write `response_type = useful`?
See §3.5's "known gap" note. Recommend yes, for consistency with manual accept, but this is a pre-existing behavior this feature happens to touch, not something explicitly requested — verify it doesn't change evaluation counts in a way that surprises anyone (e.g. check `evaluation_participant_graph_builder.dart` usage context first). **Distinct from §6.3** — recording an `autoAdmit` admission event is a hard requirement (§6.3), this question is only about the separate `response_type` column.

### 9.2 Legacy rows with no admission event
Anyone already `admitted` before this migration ships has no row in `beacon_help_offer_admission_event`. Per §4.1's table, treat "no event row" the same as "automatic" (safe default, avoids a confusing empty state) — or add a third fallback label ("Admitted" with no automatic/manual claim) if that feels more honest. Either is defensible; pick one and be consistent. Do **not** attempt to backfill history you don't have.

### 9.3 Delete the old sheet/mutation, or leave as dead code?
`coordination_response_bottom_sheet.dart` and its single call site are being removed from the UI (§3.3). Whether to also delete the file, and whether to delete/keep `CoordinationCase.setCoordinationResponse` + its GraphQL field + `mutation_coordination.dart` server-side: recommend **deleting the client-side sheet file** (confirmed single call site, clearly dead once removed) but **leaving the server mutation in place** unless a broader grep (beyond what this doc's research covered) confirms zero other callers, including tests. Deleting a mutation is more invasive/riskier than deleting a client widget; don't do it as a drive-by part of this feature unless you've specifically verified it's safe.

### 9.4 Re-decision UX (§4.4)
Flagged already — the "Accept/Decline always available on non-admitted rows" design is this plan's choice for satisfying "not terminal," not a literal transcription of a stakeholder answer. If it turns out the product owner actually wanted the committer to take an explicit resubmission action instead, that's a different (larger) change touching §3.6.2's offer-help paths.

---

## 10. Test plan

- **Server use-case tests** (wherever `CoordinationCase`/`HelpOfferCase` are tested today — find via `grep -rl "CoordinationCase\|setCoordinationResponse" packages/server/test`): new tests for `acceptHelpOffer`, `declineHelpOffer` (mandatory-reason `reasonRequired`, over-length `reasonTooLong`, and the new **`alreadyAdmitted` guard** — decline must reject when `roomAccess == admitted`), `removeFromRoom` (the **`notAdmitted` guard** — reject when not currently admitted), the author-or-steward authorization (§6.2 — a steward, not just the author, must be able to call all three; also confirm a plain non-author/non-steward participant is rejected), and the evaluation-acknowledgment invariant from §3.5 (accept → acknowledged, decline → not acknowledged).
- **Transaction-atomicity test**: force a failure partway through one of the three methods' write sequence (e.g. mock the admission-event insert to throw after the coordination-response upsert succeeds) and assert nothing committed — `roomAccess` and the coordination-response row must not diverge from "no admission event recorded." For `removeFromRoom` specifically, also assert the activity event never gets inserted if the room-access revoke fails (both are pre-commit, §6.2's corrected ordering).
- **Reason-redaction test**: query `helpOffersWithCoordination` as (a) the beacon author, (b) a steward, (c) the declined/removed committer themselves, (d) an unrelated third-party admitted participant — assert (a)-(c) see the reason and (d) sees `null`.
- **Read-access guard test**: query `helpOffersWithCoordination` as a viewer who fails `BeaconAccessGuard.canReadContent` for that beacon (§6.5) — assert rejection, not just redacted-but-returned rows.
- **Notification-port test**: `CoordinationCase`'s new `BeaconRoomNotificationPort` dependency is exercised (not just DI-wired) — assert `notifyCommitmentDeclined`/`notifyCommitmentRemoved` are actually invoked with the right `reason`/`actorUserId`, via a fake/mock port.
- **Invalidation test / manual check**: whichever option §5.3 lands on (reuse `'help_offer'` vs a new entity type), confirm a second connected client actually receives a live refresh after a decline/remove — this is easy to get wrong silently since an unrecognized `pg_notify` entity is dropped with no error.
- **Repository tests**: new admission-event table round-trips; "latest event per offer" query correctness across multiple decline→accept→remove cycles for the same offer, using `seq` (not `created_at`) as the ordering key.
- **Client widget tests**: `HelpOfferTile` rendering for each row of the §4.1/§4.2 state tables, per viewer type (author / committer / third party).
- **Client cubit tests**: optimistic-update + rollback-on-failure behavior for the three new cubit methods, mirroring however `setCoordinationResponse` is tested today.
- **l10n contract test**: `packages/client/test/l10n/request_terminology_contract_test.dart` must still pass with new keys added.
- **Manual QA** (use the `local-debug` skill / Playwright): full flow — author accepts a pending committer (card moves to Active Helpers, chat access granted), author declines with a reason (card moves to Not Fitting, committer sees the reason on their own card + gets a push), author removes an admitted committer with a reason (card moves back out of Active Helpers, remaining room members see a system message with no reason, removed committer sees the reason), forward-triggered auto-admit shows "Admitted automatically" with correct explanatory text.

---

## 11. Rollout checklist

1. Migration `m0113` written (table + `action`/`reason` CHECK constraints incl. the 500-char length cap + unique index + invalidation trigger, §5.1/§5.3), registered in `_migrations.dart`, applied to local dev DB.
2. New exception codes `reasonRequired`, `reasonTooLong`, `notAdmitted`, `alreadyAdmitted` appended to `HelpOfferCoordinationExceptionCode` (§6.2).
3. Drift table class added (§5.2) + domain entity/enum + `HelpOfferAdmissionRepositoryPort` + its repository implementation (§6.1), DI-registered.
4. Two new methods declared on the **`BeaconRoomNotificationPort` interface** first, then implemented on `BeaconRoomPushService` (§6.7) — not the other way around.
5. `BeaconRoomNotificationPort` and `BeaconAccessGuard` added as new constructor dependencies on `CoordinationCase` (§6.2, §6.5).
6. `dart run build_runner build -d` in `packages/server` (Drift codegen + DI regen — covers steps 3-5).
7. `CoordinationRepositoryPort`/`CoordinationRepository` gain `acceptHelpOffer`/`declineHelpOffer`/`removeFromRoom`, each internally opening **one** `_database.withMutatingUser(...)` block covering every write for that action (§6.2) — **not** `runInBeaconStateTransaction`, which is the wrong primitive.
8. `CoordinationCase`: thin `acceptHelpOffer`/`declineHelpOffer`/`removeFromRoom` wrappers added, calling the single repository method each, using `_ensureAuthorOrSteward` (not `_ensureAuthor`) plus the new `notAdmitted`/`alreadyAdmitted`/`reasonRequired`/`reasonTooLong` validations (§6.2) and the `BeaconAccessGuard.canReadContent` check added to `helpOffersWithCoordination()` (§6.5).
9. `helpOffersWithCoordination()` also gets per-viewer reason redaction in `CoordinationCase` (not the repository) (§6.5) — verify with a test that a non-author, non-affected viewer gets `null`, not the real reason.
10. `HelpOfferCase._autoAdmitIfTrusted()` extended to record an `autoAdmit` admission event (§6.3) — easy to forget since it's a separate code path from steps 7-8.
11. GraphQL fields added under `mutation_coordination.dart`, all returning `v2_BeaconStatusResult!` (§6.4) — **not** by extending `BeaconRoomAdmit`.
12. `beacon_notification_batch_aggregator.dart` and `beacon_notification_recipient_resolver.dart` checked for exhaustive-switch compile breaks from the new `NotificationKind` values.
13. New `BeaconActivityEventTypeBits` value added both server + client, room-visible event **inserted inside the same transaction as the room-access revoke** (before commit — §6.2's corrected ordering), payload with no reason, l10n-backed label added to `beacon_activity_event_presenter.dart` (§6.6).
14. Realtime invalidation for the new table resolved per §5.3 — default is reusing `entity: 'help_offer'` in the trigger (zero client changes); only add a new `invalidation_service.dart` case if you deliberately chose a new entity type.
15. Client `.graphql` operations added under `beacon_view/data/gql/`, `dart run build_runner build -d` in `packages/client`.
16. **New operation names registered in `_tenturaDirectOperationNames`** (`build_client.dart`, §6.4) — easy to miss, fails silently at runtime (routes to Hasura instead of V2) rather than at compile/codegen time.
17. Client domain entities extended (§7.2); repository methods added (§7.3 step 1); `BeaconViewCase` methods added with the three-call local-invalidation fan-out (§7.3 step 2, §3.7); cubit methods added calling `_case.X`, not the repository (§7.3 step 3).
18. `HelpOfferTile` + `beacon_people_tab_body.dart` rewritten per §7.4, including the card-header status-line fix (not just `_AuthorFooter`).
19. New reason dialog added, `TextField(maxLength: 500)` matching the server/DB cap.
20. l10n keys added (en + ru), terminology scripts/tests pass.
21. Old coordination sheet call site removed; file deletion decided per §9.3.
22. Tests per §10 written and passing, including: transaction-atomicity, reason-redaction, read-access-guard, notification-port, and evaluation-acknowledgment invariant tests.
23. Manual QA pass per §10 on local stack, including a two-client live-invalidation check.
