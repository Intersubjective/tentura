---
status: ready
kind: plan
---

# Backup-offer UX correction plan

**Status:** ready for execution.
**Date:** 2026-08-06.
**Scope:** a targeted correction to the already-shipped "backup offer" feature
(`enoughHelp` beacon status), delivered under phase P6 of the archived
[`commitment-truth-rework-plan.md`](../archive/plans/commitment-truth-rework-plan.md).
This plan does **not** reopen that archived plan — it is a follow-up correction
against a newer product decision. Do not edit the archived plan file.
**Journal:** [`backup-offer-primary-action-correction-journal.md`](backup-offer-primary-action-correction-journal.md)
(create on first run; not itself a work unit).

---

## 0. Why this plan exists

An audit compared the shipped implementation against this product spec (the
authoritative, newer version — supersedes the archived plan's D2 "вариант
A+B" choice where it conflicts):

1. When beacon status is `enoughHelp`, the primary "Offer help" action for a
   non-participant helper is **replaced by "Offer as backup"**.
2. "Forward" is kept as a **secondary** action in that state.
3. A backup offer: (a) appears in the People tab as **"Available as backup"**;
   (b) appears in the beacon's activity/timeline; (c) is always visible to the
   author.
4. The author gets a **normal-priority** notification: "Anna offered to help
   as backup."
5. The UI/notification must **not** show "someone is waiting on you" /
   immediate-response language for backup offers.
6. The offering user sees: "Your backup offer was sent to the author. They
   may contact you if more help is needed."
7. Backup offers are **never auto-activated** or auto-moved between states by
   the system.
8. To activate a backup offer, the author must move the beacon out of
   `enoughHelp` back to an open/needs-help state and contact a backup
   directly — no one-click "activate this backup offer" affordance.

Audit result — what's already correct vs. what needs to change:

| # | Verdict | Action |
|---|---|---|
| 1 | **mismatch** — code makes Forward primary, backup-offer secondary (inverted) | **fix (P1)** |
| 2 | **mismatch** — same defect, other side | **fix (P1)** |
| 3a | **mismatch** — label is "Backup" (chip) / "Backup offers" (heading), not "Available as backup" | **fix (P2)** |
| 3b | match (beacon Timeline tab) | no change |
| 3c | match (unconditional visibility) | no change |
| 4 | **partial** — priority already normal, but copy is generic "X offered help", not backup-specific | **fix (P3)** |
| 5 | match, but vacuously (no backup-specific handling exists at all yet) | **lock in with a test (P4)** |
| 6 | **mismatch** — no such confirmation copy exists; same generic "Forward it to someone?" nudge is shown for both kinds | **fix (P2)** |
| 7 | match | **lock in with a test (P4)**, no behavior change |
| 8 | match (`needsMoreHelp` / "Needs more help" is the semantic equivalent; no rename needed) | no change |

**Do not touch** anything covered by "no change" rows above — this is a
correction, not a rewrite. Do not rename `BeaconStatus.needsMoreHelp` or its
label; the spec's "More or different help needed" is a description of the
target state, not a mandated literal string, and this status already reads
correctly in the UI ("Needs more help").

## 1. Rules (repo-wide invariants — read before editing)

- Never hand-edit generated files: `*.g.dart`, `*.freezed.dart`, `*.gr.dart`,
  `*.config.dart`, `packages/client/lib/ui/l10n/**`, `**/_g/**`. Only run
  codegen.
- After editing `packages/client/l10n/*.arb`: `cd packages/client && flutter
  gen-l10n` (before any client `build_runner`).
- After editing Drift tables / Injectable / Freezed classes on the server:
  `cd packages/server && dart run build_runner build -d`.
- After editing Freezed/Injectable on the client: `cd packages/client && dart
  run build_runner build -d`.
- No raw visual constants in client UI (`Color`, `TextStyle(...)`,
  `EdgeInsets.all(8)`, …) — only design-system tokens (`context.tt`,
  `TenturaText.*`). The button-swap in P1 reuses existing widgets/tokens; it
  must not introduce new raw constants.
- Do not widen scope. If something outside this plan looks broken while
  working, note it in §6 "Out of scope / follow-ups" instead of fixing it
  inline.
- Preserve all pre-existing uncommitted changes in the working tree (there are
  unrelated in-progress doc edits in `docs/Tentura_current_status_quo.md`,
  `docs/features/beacon_room.md`, `CONTEXT.md`, and a few server files as of
  plan authoring — diff them first, edit around them, never revert them).

## 2. Verification commands

```bash
cd packages/tentura_lints && dart test
cd packages/server && dart test -x pg        # no local Postgres required
cd packages/client && flutter test
```

Run the relevant subset after each phase (server tests after P3/P4-server,
client tests after P1/P2/P4-client); run the full set at the end.

---

## Phase P1 — Client: swap primary/secondary action for `enoughHelp`

**File:** `packages/client/lib/features/beacon_view/ui/widget/beacon_operational_header_card.dart`

In `_buildHelperHudActions`, the `enoughHelp` branch (currently lines
~134–151) builds `primary = [Forward]` (filled) and puts "Offer as backup" in
`secondaryLabel`/`onSecondary`. Invert this:

- `primary` becomes `[_HudActionSpec(icon: Icons.volunteer_activism_outlined,
  label: l10n.beaconOfferHelpAsBackup, onPressed: onOfferHelp, filled: true)]`
  (only added when `onOfferHelp != null`, matching the existing null-guard
  style used elsewhere in this method).
- `secondaryLabel`/`onSecondary` becomes `l10n.labelForward`/`onForward`
  (only set when `onForward != null`).

Keep everything else in the method (the `deleted`/`closed`/`cancelled` guard,
`isBeaconMine` guard, steward/reviewOpen/`!openFamily` guard, and all other
branches below the `enoughHelp` branch) untouched — this phase only inverts
the two fields inside this one branch.

**Acceptance:** on a beacon with status `enoughHelp`, viewed by a non-mine,
non-steward, non-offered helper, the filled primary button reads "Offer as
backup" and triggers `onOfferHelp`; a text-link secondary action reads
"Forward" and triggers `onForward`. No other HUD branch's rendering changes.

**Verification:** `cd packages/client && flutter test` (existing widget/golden
tests touching `BeaconOperationalHeaderCard` or `_buildHelperHudActions`, if
any — search `test/` for `beacon_operational_header_card` first; add a widget
test asserting the swap if none currently cover this branch).

Commit this phase's change on its own before moving to P2.

---

## Phase P2 — Client: People-tab label + backup-offer confirmation copy

### P2.1 — People-tab badge wording

**File:** `packages/client/l10n/app_en.arb` / `app_ru.arb`

Change the value of `helpOfferBackupBadge` (key stays the same — only the
call sites in `help_offer_tile.dart:216` read it, no rename needed):

- en: `"Backup"` → `"Available as backup"`
- ru: `"Запасной"` → pick a natural equivalent, e.g. `"На подхвате"` (already
  used as the group-heading translation for `helpOffersBackupGroupTitle`) or
  `"Доступен как запасной"` — use judgment for natural Russian phrasing, this
  is a UI chip label so keep it short.

Do **not** change `helpOffersBackupGroupTitle` ("Backup offers" / group
heading in `beacon_people_tab_body.dart:385`) — the spec only specifies the
per-offer label, and the section heading is a separate, already-correct
piece of copy.

Run `cd packages/client && flutter gen-l10n` after editing the `.arb` files.

### P2.2 — Confirmation message on submitting a backup offer

**File:** `packages/client/lib/features/beacon_view/ui/message/help_offer_messages.dart`

Add a new message class, following the existing `MovedToInboxMessage`
pattern (plain `LocalizableMessage`, no action button):

```dart
final class BackupOfferSentMessage extends LocalizableMessage {
  const BackupOfferSentMessage();

  @override
  String get toEn =>
      'Your backup offer was sent to the author. '
      'They may contact you if more help is needed.';

  @override
  String get toRu =>
      'Ваше предложение помощи как запасного варианта отправлено автору. '
      'Он может обратиться к вам, если понадобится больше помощи.';
}
```

**File:** `packages/client/lib/features/beacon_view/ui/bloc/beacon_view_cubit.dart`

In `offerHelp()` (currently ~lines 363–385), capture whether the beacon was
in `enoughHelp` *before* the mutating call (the fetch afterward may change
`state.beacon`, so read it first):

```dart
Future<void> offerHelp({
  required String message,
  List<String>? helpTypes,
}) async {
  final wasAlreadyHelpOffered = state.isHelpOffered;
  final wasEnoughHelp = state.beacon.status == BeaconStatus.enoughHelp;
  emit(state.copyWith(status: StateStatus.isLoading));
  try {
    await _case.forwardOfferHelp(
      beaconId: state.beacon.id,
      message: message,
      helpTypes: helpTypes,
      notifyHelpOfferListeners: !wasAlreadyHelpOffered,
    );
    await _fetchBeaconByIdWithTimeline();
    if (!state.hasError && !wasAlreadyHelpOffered) {
      _effects.emit(
        ShowMessage(
          wasEnoughHelp
              ? const BackupOfferSentMessage()
              : HelpOfferedForwardNudgeMessage(state.beacon.id),
        ),
      );
    }
  } catch (e) {
    _showSnackError(e);
  }
}
```

`BeaconStatus` is already imported in this file (used elsewhere in the
cubit) — confirm the import exists before assuming; add it if not.

**Acceptance:** offering help while the beacon is `enoughHelp` shows the new
backup-offer confirmation (no Forward action button); offering help in any
other open state still shows the existing forward-nudge snackbar unchanged.

**Verification:** `cd packages/client && flutter test` — add/extend a cubit
test for `offerHelp()` asserting the message-class branch on `wasEnoughHelp`.

Commit P2.1 and P2.2 together (one coherent "backup-offer copy" step) after
verification.

---

## Phase P3 — Server: distinct notification copy for backup offers

### P3.1 — Thread an `isBackupOffer` flag through the notification intent

**File:** `packages/server/lib/domain/entity/beacon_notification_intent.dart`

Add a new Freezed field alongside the existing `promiseWithdrawn` flag,
following the identical pattern:

```dart
@Default(false) bool isBackupOffer,
```

**File:** `packages/server/lib/domain/use_case/attention_intent_case.dart`

In `helpOfferSubmitted` (~lines 58–76), add a parameter and pass it through:

```dart
Future<AttentionDispatchIntent> helpOfferSubmitted({
  required String beaconId,
  required String helpOffererId,
  required String authorId,
  required String sourceEventKey,
  List<String> moderatorUserIds = const [],
  bool isBackupOffer = false,
}) => fromBeaconNotification(
  notification: BeaconNotificationIntent(
    kind: NotificationKind.commitmentEvent,
    priority: NotificationPriority.normal,   // unchanged — see P4/point 5
    beaconId: beaconId,
    actorUserId: helpOffererId,
    targetPersonId: authorId,
    moderatorUserIds: moderatorUserIds,
    isBackupOffer: isBackupOffer,
  ),
  eventType: AttentionEventType.helpOfferSubmitted,
  sourceEventKey: sourceEventKey,
  targetEntityId: helpOffererId,
);
```

Do not change `priority` — it must stay `NotificationPriority.normal` for
both kinds (this is what point 5 requires: no elevated urgency).

**File:** `packages/server/lib/domain/use_case/help_offer_case.dart`

At the call site (~line 144), pass `isBackupOffer: offerKind == 1` (the
`offerKind` local is already computed at line 111–112 in this method).

**File:** `packages/server/lib/domain/use_case/beacon_room_case.dart`

The other call site (~line 735, `offerHelp` for already-admitted room
participants) has no `offerKind` concept — leave it passing the default
(`isBackupOffer: false`, i.e. don't pass the parameter at all). Confirm this
by checking whether `beacon_help_offer.offer_kind` is even written on that
path; if it is not, this is correct as-is and needs no change.

### P3.2 — Differentiate the copy

**File:** `packages/server/lib/domain/notification/beacon_notification_copy_builder.dart`

In the `NotificationKind.commitmentEvent` branch (~lines 122–133), add a
third case for backup offers, keeping the existing excerpt-priority
behavior:

```dart
NotificationKind.commitmentEvent =>
  intent.promiseWithdrawn
      ? (
          actor,
          excerpt.isNotEmpty ? excerpt : '$actor withdrew their help',
        )
      : intent.isBackupOffer
          ? (
              actor,
              excerpt.isNotEmpty
                  ? excerpt
                  : '$actor offered to help as backup',
            )
          : (
              actor,
              excerpt.isNotEmpty ? excerpt : '$actor offered help',
            ),
```

Run `cd packages/server && dart run build_runner build -d` after the Freezed
field addition (P3.1) before running server tests.

**Acceptance:** a help offer submitted while the beacon is `enoughHelp`
produces a notification body "$actor offered to help as backup" at normal
priority; a normal-state offer still produces "$actor offered help"
unchanged; a withdrawal is unaffected.

**Verification:** extend
`packages/server/test/domain/notification/beacon_notification_copy_builder_test.dart`
(follow the existing `intent({...})` test helper and the
`promiseWithdrawn`-branch test at ~line 107 as a template) with a case:
`isBackupOffer: true` → `copy.body == 'Someone offered to help as backup'`.
Also extend `packages/server/test/domain/use_case/help_offer_case_test.dart`
(or the nearest existing test for `offerHelp`, if the filename differs —
search first) to assert `isBackupOffer` is `true` on the recorded intent when
`beacon.status == BeaconStatus.enoughHelp`, and `false` otherwise.

```bash
cd packages/server && dart test -x pg
```

Commit P3.1 and P3.2 together after verification.

---

## Phase P4 — Regression tests locking in points 5, 7, 8 (no behavior change)

These three points already match the spec; add tests so future changes can't
silently regress them. No production code changes in this phase.

1. **Point 5 (no urgency for backup offers):** a test asserting
   `AttentionIntentCase.helpOfferSubmitted(..., isBackupOffer: true)` still
   produces `NotificationPriority.normal` (not elevated) — extend or add
   next to the P3.1 test coverage.
2. **Point 7 (no auto-activation):** confirm existing coverage — check
   `packages/server/test/domain/evaluation/evaluation_case_test.dart:1554`
   ("does not record unansweredAtClose for backup offers") and search for any
   test that asserts `offerKind` is preserved across a beacon status
   transition (e.g. `enoughHelp` → `needsMoreHelp` → back). If no such test
   exists, add one in `packages/server/test/domain/use_case/coordination_case_test.dart`
   (or nearest matching file) asserting a backup offer's `offerKind` is
   unchanged after the author changes beacon status.
3. **Point 8 (no one-click activate):** this is a structural absence, not
   behavior to unit-test — skip a dedicated test; instead do a final
   confirmation grep (`grep -rn "activate" packages/client/lib packages/server/lib
   | grep -i backup`) and record a zero-result finding in the journal.

**Verification:**
```bash
cd packages/server && dart test -x pg
```

Commit any new tests from this phase on their own.

---

## Phase P5 — Documentation

### P5.1 — `docs/Tentura_current_status_quo.md`

Around the existing §8.2 paragraph (currently ends with: "the primary public
action for uninvolved viewers becomes **Forward**"), update to match the
corrected UX:

> At **enough help**, new offers are **not blocked** — they are submitted as
> **backup offers** (secondary coordination; the primary public action for
> uninvolved viewers becomes **Offer as backup**, with **Forward** available
> as a secondary action). The author coordinates openly across primary and
> backup offers.

Preserve the surrounding uncommitted edits already in this file (diff first
— there are unrelated in-progress additions around §8.1/§8.3/§8.4 as of plan
authoring; edit only the sentence identified above, do not revert anything
else).

### P5.2 — `docs/features/beacon_room.md`

Expand the existing "Backup offers" paragraph (~line 74) to document the
corrected behavior — primary/secondary ordering, the People-tab label, the
non-urgent notification, and the submitter-facing confirmation copy:

> **Backup offers:** when the beacon signals **enough help**, additional help
> offers are allowed as **backup** offers — secondary coordination that does
> not trigger "offers awaiting author" pressure on the author. For an
> uninvolved viewer in this state, **"Offer as backup" becomes the primary
> action** (Forward remains available as secondary). A backup offer appears
> in People as **"Available as backup"**, is always visible to the author,
> and generates a normal-priority notification ("X offered to help as
> backup") — never elevated urgency. The offering user sees a confirmation
> that their offer was sent and the author may reach out if more help is
> needed. Backup offers are never auto-activated; the author must move the
> beacon back to an open/needs-more-help state and contact a backup
> directly.

### P5.3 — New terminology note (optional, only if useful)

If `.cursor/rules/terminology.mdc` or a similar doc enumerates user-facing
status labels, no change is needed there — this plan does not rename any
status. Skip unless the worker finds an existing doc that explicitly
mis-describes the button ordering (grep `docs/` and `.cursor/rules/` for
"Forward" near "enough help" / "enoughHelp" beyond the two files above before
concluding this).

**Verification:** none (docs-only) — proofread for consistency with the code
changes from P1–P3.

Commit P5 on its own.

---

## 6. Out of scope / follow-ups

If, while executing, something adjacent looks wrong but is not one of the 8
spec points above (e.g. `helpOffersBackupGroupTitle` wording, activity-feed
vs. per-beacon-timeline terminology, `needsMoreHelp` status naming), do not
fix it — record it here in the journal as a follow-up candidate and move on.
