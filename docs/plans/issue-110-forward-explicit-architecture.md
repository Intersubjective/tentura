---
status: ready
kind: architecture
issue: 110
---

# Explicit forwarding — architecture

**Status:** architecture **rev 3**, implementation-ready. Shape only — no
file-by-file task list. Product decisions in §2 bind
[`issue-110-forward-explicit-implementation-plan.md`](issue-110-forward-explicit-implementation-plan.md).

**Issue:** [#110](https://github.com/Intersubjective/tentura/issues/110)
(parent [#96](https://github.com/Intersubjective/tentura/issues/96), UX-03 plus
the relay-note contract).

**Product UX** (locked): visible personal note with explicit skip / shared-note
sheet; stay on Forward after send; switch to **Already in the chain** when at
least one edge was delivered; flash just-delivered rows; toast always names
**where the request is for ego**; Watching CTA only when that place is Inbox
Watching; hide Forward where `!allowsForward`. User-facing copy: **request** /
**chat**.

**Rev 3** closes Opus CLI findings against rev 2: D9 uses GetIt
`HomeTabReselectCubit` (not `InboxCubit`); `hasOnwardChild` is mandatory;
every standalone `forward()` drops `NavigateBack`; embedded create is exempt
from `allowsForward` UI gates; D8 is the Involved tab itself; D13 is a
before/after edge-count delta; D15 removes the watching `pendingMovedNudge`;
person-forward cancel is **added**; one combined toast for mixed delivery.

---

## 1. What this is

A **client-orchestration and entry-gate** change on the existing forward
feature, plus small server alignments:

- compose `perRecipientNote ?? sharedNote` per edge (**unchanged**; `""` on the
  map is not null — D2);
- reject forward when `!beacon.allowsForward` (open family);
- **cancel** an ego outgoing edge only while unread, with no child of **this**
  edge, no active help offer on the recipient, and **not declined**
  (`ForwardEdgeEntity.recipientRejected` — already written by inbox reject;
  `cancelForward` must start honouring it).

No parallel Request entity, no new mutation, no second forwarding engine.

`CandidateInvolvement.forwardedByMe` is **ego** (`edge.senderId == JWT sub`).
It is not a cancel-refuse reason.

Today’s cancel chrome is `forwardEdgeId != null` (too permissive). Replace
that gate with the D14 helper. Do not hunt for an `involvement == forwardedByMe`
check that does not exist.

---

## 2. Binding decisions

| ID | Decision |
|----|----------|
| **D1** | Coverage is cubit session + a pure helper. Skip is an explicit id set. |
| **D2** | Effective note = `personalIfNonEmpty ?? shared`. **Wire:** omit skipped and empty keys. Never `""`. Cubit may still hold typed text under skip until Submit. |
| **D3** | Reason slugs optional. No skip/sheet for reasons. `+N` is presentation over `recipientReasons`. |
| **D4** | Standalone `forward()` / person-forward `send()` use `beacon.allowsForward`, not `status == open`. **Embedded create is exempt:** the picker runs on a `draft`; `sendRequest` publishes first, then `forward()`. Embedded `canSubmit` is selection ∧ no uncovered — not `allowsForward`. |
| **D5** | Standalone Forward **CTAs** hide unless `allowsForward`. Not the embedded create Send button. `CardTriageActionRow.onForward` nullable. My Work author footer: `!authorHasForwardedOnce && allowsForward`. Null `InboxItem.beacon` → hide Forward. Forwards graph is not a Forward CTA. |
| **D6** | Standalone route on a non-forwardable beacon: read-only chain, no send. |
| **D7** | **Every** standalone `forward()` path drops `NavigateBack`, including the all-paused early return and zero-delivery. ≥1 delivered: `reloadCandidates(forceReload: true)`; filter → `alreadyInvolved`; flash delivered ids; clear draft. Zero delivered: stay on current filter; no flash; no location toast; availability toast only. **Also** `cancelForward` and `saveForwardEdit` must `forceReload: true` (today they call `_loadCandidates()` and the memo discards the fetch; client cancel does not emit `forwardChanges`). Embedded: no D7/D9; host dialog + pop. Keep `_suppressForwardChangeReload` during send. |
| **D8** | **Superseded (2026-09-02):** show the bottom composer on `alreadyInvolved` as well — Involved includes eligible `watching` / `forwarded` recipients who can still be sent to. Composer hide is **not** keyed on filter tab or `lastDeliveredRecipientIds`; use existing D5–D6 / `allowsForward` read-only gates and (person-forward) hide send when no eligible row is selected. Selection is kept across Unseen ↔ Involved. |
| **D9** | Standalone ≥1 delivery: **one** `ShowMessage`. It names ego home (**Watching** vs **My Work**). If some recipients were availability-paused, the **same** string includes the existing partial-pause clause (do not emit a second snackbar). Watching CTA only when ego home is Watching (not author, no active help offer). **Action seam (executable):** GetIt `@singleton` `HomeTabReselectCubit.requestInboxWatching(beaconId)` (intent survives Home rebuild), **then** `NavigateReplaceTarget.homeInboxTab` / `replaceAll` Inbox. `InboxCubit` is **not** in GetIt and is destroyed by `replaceAll` — do not store intent there. `InboxScreen` consumes the intent in `initState` and on count change: `animateTo(1)`. **Expanded:** also select that watching card if it is still in the list. **Compact:** Watching **list** only — do not set `_selectedWatchingBeaconId` (that would skip the list). Author/help-offer: My Work copy, no CTA. Flags on `ForwardLoad`. |
| **D10** | Pause ≠ decline. Paused ids never enter flash / involved. |
| **D11** | Shared functions: coverage, D14 cancel, `allowsForward`. Person-forward: one person, one selected beacon, one `note`; skip → `note: null`. **Add** cancel chrome on `alreadySent` (it does **not** exist today — `PersonForwardCubit` has no cancel; the row pushes `ForwardBeaconRoute`). Row must carry ego `forwardEdgeId` + D14 flags. `notOpen` stays in `blockFor`; fetch remains open-family. |
| **D12** | Domain: no Flutter/router. Cubits: `UiEffect` only. `LocalizableActionMessage.onPressed` may `GetIt` (`RootRouter`, `HomeTabReselectCubit`). |
| **D13** | Offer-help nudge is **not** `pop(true)` and **not** “ever forwarded this beacon”. Opener snapshots outgoing-edge count / `hasForwardedThisBeaconOnce` **when pushing** Forward. After pop (any result, including Close), re-read; nudge iff the count **increased** and offer-help is still allowed. Browsing the chain with zero new edges must not nudge. Do not show this nudge while Forward still covers the opener. |
| **D14** | Cancel visibility helper (and server `cancelForward`): unread; no child of this edge; no recipient active help offer; **not** `recipientRejected`. Today’s UI gate `forwardEdgeId != null` is the leak to replace. **`hasOnwardChild` is mandatory** on `MyForwardRecipient` (compute in `BeaconInvolvementCase` from the already-fetched edge list: any other edge has `parentEdgeId == this.id`). Also expose `recipientRejected` on that DTO from the same edge. Do not infer child from `onwardForwarderIds`. |
| **D15** | `_fetchAndNotifyIfMoved` must **not** emit `pendingMovedNudge` when `toStatus == watching`. That stream is only own `forwardCommandCompleted`; D9 replaced that snackbar. Leave the rejected branch. Comment at the site. Update the test that currently expects a watching nudge from `emitForwardCommandCompleted`. |

---

## 3. Layer allocation

```
┌─────────────────────────────────────────────────────────────┐
│ UI  picker / sheet / flash / HomeTabReselectCubit intent    │
│     ForwardCubit / PersonForwardCubit                       │
│     TextEditingControllers = widget projections             │
├─────────────────────────────────────────────────────────────┤
│ Domain  coverage, D14 cancel helper, allowsForward          │
├─────────────────────────────────────────────────────────────┤
│ Data    omit empty/skipped keys                             │
│ Server  cancelForward + recipientRejected; mandatory        │
│         hasOnwardChild + recipientRejected on               │
│         MyForwardRecipient (computed, no new table)         │
└─────────────────────────────────────────────────────────────┘
```

**Domain functions** (exact names for the implementation plan):

```dart
Set<String> uncoveredRecipientIds({
  required Set<String> selectedIds,
  required Map<String, String> perRecipientNotes,
  required Set<String> skippedPersonalNoteIds,
});

String? effectiveForwardNote({String? personal, String? shared});

bool forwardEdgeIsCancellable({
  required DateTime? recipientReadAt,
  required bool hasOnwardChild,
  required bool recipientHasActiveHelpOffer,
  required bool recipientDeclined,
});
```

`ForwardCandidate` / `PersonForwardRow` carry the four D14 inputs plus
`forwardEdgeId`. Helpers stay free of Flutter.

`ForwardLoad` also: `hasMyOutgoingForward` (exists); `viewerIsAuthor`;
`viewerHasActiveHelpOffer`.

**Cubits**

`ForwardState`: `skippedPersonalNoteIds`, `lastDeliveredRecipientIds`; existing
note maps. Controllers are not in the cubit.

Standalone `forward()`:

1. `!allowsForward` → refuse (no English `Exception` snack as the UX).
2. Uncovered → no network.
3. Maps omit empty/skipped keys.
4. **Never** `NavigateBack`.
5. ≥1 delivered → location(+pause) toast, force-reload, `alreadyInvolved`, flash,
   clear draft + reset controllers.
6. 0 delivered → availability toast only.

**Watching action**

```
HomeTabReselectCubit.requestInboxWatching(beaconId)
→ NavigateReplace.homeInboxTab
→ InboxScreen.initState / listener: animateTo(1);
   expanded && item present → _selectedWatchingBeaconId = beaconId
   compact → list only
```

---

## 4. Session vs committed truth

| Concern | Where | After kill |
|---------|-------|------------|
| Draft notes / skip | Cubit | Lost |
| Flash ids | Cubit | Lost |
| Controllers | Widget, must match cubit | Lost |
| Edges, notes, `recipientRejected`, children | Server | Survives |
| Watching / My Work stance | Server | Survives |
| Watching open intent | `HomeTabReselectCubit` (process) | Lost |

---

## 5. Effects

| Event | Effect |
|-------|--------|
| Standalone any outcome | **Not** `NavigateBack` |
| ≥1 delivery | One `ShowMessage` (location; pause clause if mixed; CTA if Watching) |
| 0 delivery | Availability `ShowMessage` only |
| Open in Watching | Message `onPressed`: reselect cubit + `homeInboxTab` |
| Embedded success | Host dialog + pop; no D9 |
| Cancel/update hard fail | `ShowError` |

No undo line.

---

## 6. Dual-surface

```
Request → ForwardBeaconScreen → ForwardCubit
Profile → PersonForwardScreen → PersonForwardCubit
Create recipients → ForwardCubit(embedded: true)  // D4/D5/D7/D9 carve-out
```

Person-forward: stay; `load()` after send; flash `alreadySent`; same toast
family; **add** cancel on `alreadySent`; skip/sheet on the one note.

---

## 7. CTA inventory

Predicate: `beacon != null && beacon.allowsForward`. Hide, do not disable.

| Surface | Today | This work |
|---------|-------|-----------|
| Inbox **Needs me** `CardTriageActionRow` | Always `onForward` | Nullable; hide if no beacon / `!allowsForward` |
| Inbox **Watching** | `showCtaRow: false` | No card Forward CTA (overflow already gated) |
| Inbox overflow | `allowsForward` | Keep |
| Request app bar / HUD | `allowsForward` | Keep |
| My Work overflow | `allowsForward` | Keep |
| My Work footer / phase Forward | `!authorHasForwardedOnce` only | AND `allowsForward` |
| Help-offer snackbar → Forward | Always push | No-op if `!allowsForward` |
| Rejected archive `onTap` → Forward | Always push | Gate; null beacon → do not push Forward |
| Embedded create Send | Draft, `!allowsForward` | **Exempt** (D4) |

Route `/forward/…` still D6 if opened anyway.

---

## 8. Disambiguations

**Skip wire.** Omit key. `""` blocks shared.

**D8.** Superseded: Involved tab shows composer so eligible chain members
(`watching` / `forwarded`) can be selected and sent. Hide is not filter-based.

**D13.** Delta across the Forward **visit**, not lifetime `hasMyOutgoingForward`.

**D15.** The watching `pendingMovedNudge` **is** the own-forward snackbar.
Removing it for `watching` is deletion of that duplicate, not a filter with a
second producer.

**Mixed toast.** One string: location + pause. Never two `ShowMessage`s.

**Compact Watching.** Tab only, not a selected card.

**Gesture / focus.** Unchanged from rev 2: isolated hit targets; toast must not
steal focus; flash first row for a11y.

---

## 9. What not to change

- `beaconForward` mutation shape / `recipientReasons`.
- Server `??` composition and `allowsForward`.
- MeritRank, band, lineage, invite-from-forward.
- Watching as a third primary Inbox-card action.
- A `Request` type; user-facing “beacon/room”.
- Loading closed beacons onto person-forward for `notOpen`.
- Purifying client `ForwardCase` → `ForwardRepository` imports.
- `Open in My Work` CTA (copy only).
- Auto-navigate to Watching (CTA is explicit).

Allowed deltas: `cancelForward` honour `recipientRejected`; GQL
`MyForwardRecipient.hasOnwardChild` + `recipientRejected` (computed from
edges already in `fetchByBeaconId` — no migration).

---

## 10. Test seams

- Helpers: coverage, effective note, D14 (including declined + has-child).
- Server: `cancelForward` false when `recipientRejected`.
- Involvement: `hasOnwardChild` true iff a fetched edge has this id as parent.
- Cubit: no `NavigateBack` on success **or** all-paused; force-reload after
  send/cancel/edit; skip ids omitted; zero-delivery does not switch filter;
  embedded `canSubmit` without `allowsForward`.
- Inbox: watching command-completed does not set `pendingMovedNudge`;
  `requestInboxWatching` + new screen lands on tab 1.
- D13: pop after a real new edge nudges; pop with no new edge does not.
- CTA: Needs me hides Forward when `!allowsForward`; My Work footer AND.

---

## 11. Out of scope

Pre-submit who-gets-what wizard · auto-navigate to Watching · snackbar undo ·
reason skip/apply-to-all · retry-to-paused · cancel from Inbox Watching cards ·
changing who may read a note · compact auto-open of a watching detail pane.
