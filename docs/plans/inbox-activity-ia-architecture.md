# Inbox → Activity: information architecture — architectural proposal

Status: architectural proposal, revision 5. Not an implementation plan. No application, API, schema, or data changes are authorized by this document alone.

Date: 2026-09-09. Repository baseline inspected: `c6b24012d`, including the current working tree.

Revisions 1–4 passed through five independent adversarial review passes (§15). Mechanics withdrawn under them are listed in §13 so they are not silently reintroduced. Revision 5 responds to the rev 4 pass, which rejected it on one blocking and five major findings — chiefly that §8.1 is a server contract, not a client-side scope edit. User-facing **Request** remains internal **Beacon**; this proposal adds no parallel entity, table, or route family.

## Product decisions supplied by the product owner

| Area | Decision |
|---|---|
| Branch label | The Inbox branch becomes user-facing **Activity** / «Активность». Branch identity stays `inbox`. |
| Obligation surface | Live obligations (`requiresAction` receipts) belong to **My Work**, not Activity. The feed's "Needs you" view leaves the Activity branch. |
| Coordination items | Ask, Blocker and Promise are retired. **Plan is also retired as a coordination item** — the product's "plan" is now the free-text NOW line on the room. The remaining coordination-item machinery is dead and is to be removed. |
| Prompt-class updates | Optional, decaying, server-settleable actions (today: invite-accepted capability setup) are **placed**, never counted in a badge. |
| Watching | Remains a reachable Request collection, not a filter over receipts. |

## 1. Problem

The Updates feed sits as the third tab inside the Inbox branch (`inbox_screen.dart:411-417`: "Needs me (N)" / "Watching" / "Receipts (N)"). It is not reachable without entering Inbox and moving right twice.

**1.1 The exterior signal is incomplete, not absent.** `HomeAttentionCubit._refreshMarkers` calls `AttentionCase.unreadForBeacons` (`home_attention_cubit.dart:148`), which the server resolves against unseen rows in `notification_outbox` (`server/.../attention_repository.dart:24-48`). The query candidate set is `inbox ∪ myWork` (`home_attention_cubit.dart:125-128`), whose inbox half is built from `needsMe ∪ watching` (`inbox_needs_me_reporter.dart:27-36`). Consequently receipts about anything outside those Request sets — trust changes, `invite_accepted`, `mutual_connection_formed` — never light either destination, though `InboxReceiptsTabLabel` (`inbox_receipts_tab_label.dart:18`) shows them in the global unread total once the user is already inside. Overlapping membership resolves in My Work's favour (`home_attention_state.dart:29-30`), and the active branch suppresses its own dot (`:46-50`).

The defect is **coverage**, not disconnection.

**1.2 One destination carries three peer surfaces** with no legible way to distinguish "you owe someone an answer" from "something happened".

**1.3 Objects with different lifecycles are presented as peers.** §2 sets out the actual classes.

**1.4 The "Needs you" view currently shows another branch's content.** This is a shipped defect, not a risk introduced by this proposal. See §3.

## 2. Object classes

Four classes exist. Each has a different lifecycle, and each therefore earns a different treatment.

### 2.1 Triage items — someone else's Request, your decision

An Inbox row keyed by (user, Request) with a status machine: `needsMe → watching / rejected / closedBeforeResponse / deletedBeforeResponse` (`inbox/domain/enum.dart`, `server/.../m0014.dart:71`). Created by forwards. Settled through `inbox_set_status`, and **reversible** — stop-watching (`inbox_cubit.dart:281`) and restore-rejected (`:293-296`) both return an item to `needsMe`.

Its affordances are **Offer help** (primary, opening a dialog and submitting a separate operation), **Forward**, **Watch**, and **Dismiss** (`card_triage_action_row.dart:12`, `inbox_screen.dart:753-760`, `:839-859`). There is no accept/decline gesture; Watching is not acceptance. Nothing in this proposal changes these actions.

### 2.2 Obligations — your own work, someone else's move

Receipts with `requiresAction && settlementKind == null` (`attention_receipt.dart:27,36`), aggregated server-side as `needs_you_total`. Settled by an explicit per-receipt "Mark done" gesture (`attention_case.dart:248-253`).

With Ask, Blocker, Promise **and Plan** retired (`DiscussionProductPolicy.retiredCoordinationKinds`, and the product decision above), the live producers are exactly two:

| event | producer | recipients |
|---|---|---|
| `helpOfferSubmitted` | `help_offer_case.dart:148`, `beacon_room_case.dart:904` | `authorOfBeacon` only (`attention_policy.dart:269-271`) |
| `reviewOpened` | `evaluation_case.dart:323` | `reviewerIds` (`:326`) — author, active helpers, **and `formerCommitter`** (`evaluation_participant_role.dart:6`, `evaluation_case.dart:1295,1393`) |

Dead producers, retained only by DI and tests: `needsMe` (only `publish_draft_ask_case.dart:83` and `mark_ask_case.dart:83`), `staleReminder` (only `remind_coordination_item_case.dart:92`, which rejects retired kinds), `blockerOpened` and `commitmentRedirected` (retired kinds only). See §10.

`helpOfferSubmitted` is cleanly inside My Work. `reviewOpened` is **not**, in one case: My Work's scope query admits authored non-archived Requests plus help offers with `status: {_eq: 0}` — active offers only (`my_work/data/gql/my_work_fetch.graphql:6-21`). A `formerCommitter` — someone who offered help, withdrew, and whose Request then closed — receives a review obligation while holding no My Work row. `MyWorkReviewWindows` does not close this gap: it takes `beaconIds` as input (`my_work_review_windows.graphql:1`) and so never runs for a Request outside the set.

**The allocation therefore requires §8.1.** Without it, moving obligations to My Work makes the former-committer's review obligation unreachable from either destination.

### 2.3 Prompts — an optional, decaying invitation to act

An update carrying an action that (a) nobody is blocked by, (b) has server-side settle state, and (c) loses value with time. Today's sole member is `invite_accepted`, whose state is `PromptStateValue { pending, answered, skipped }` driven through `InviteAcceptedSetupPort.answer` / `.skip` (`invite_accepted_setup_case.dart:20-25`).

The state is keyed **per invitee**, not per (inviter, invitee): the table's `primaryKey => {inviteeUserId}` (`server/lib/data/database/table/invite_seed_prompt_state.dart:24`), even though the freezed entity carries `inviterUserId` alongside (`domain/capability/invite_seed_prompt_state.dart:10-13`). A re-invite of the same person by a different inviter therefore reuses one row; §5.6 states the rule.

It is deliberately **not** `requiresAction` — `inviteAccepted` falls through to `_ => false` in `AttentionPolicy._requiresAction`. That is correct: `skipped` is a legitimate terminal outcome.

Candidate future member: `mutual_connection_formed`, which already shares the invite-accepted glyph treatment (`updates_feed_tile.dart:41`), if it is given equivalent prompt state. The rules in §5 are written for the class, so a second member does not create a fourth mechanic.

### 2.4 News — everything else

Trust changes, room messages, coordination churn, request status changes. Read/unread only.

Note that a receipt is **not** an immutable event: an unseen receipt with a matching collapse key rewrites copy, source identity, timestamp and `collapsed_count` (`server/.../attention_dispatch_repository.dart:125`). Any design that treats the feed as an append-only log is wrong.

## 3. Surface allocation

| Class | Surface | Signal |
|---|---|---|
| Triage items (§2.1) | **Activity** | numeric badge |
| Obligations (§2.2) | **My Work** | numeric badge (after §9) |
| Prompts (§2.3) | **Activity** | placement, never a badge |
| News (§2.4) | **Activity** | dot |

The split is by **ownership of the subject**, which is the axis the bottom bar already encodes: Work is "mine, and what is moving in it"; Activity is "what people sent me, and what happened".

This corrects a shipped defect. The feed's "Needs you" view (`updates_feed_pane.dart:135`, `AttentionView` in `attention_feed.dart:8`) filters on `requiresAction`. With §2.2's producer set, it today shows help offers on the user's own Requests plus reviews on Requests the user authored **or took part in** — reviewers include non-forwarding participants (`evaluation_case.dart:300-326`). All of it is My Work's content by §8.1's scope, rendered inside the Inbox branch.

## 4. The Activity branch

**4.1 The TabBar is removed.** Three tabs, one of which is an event log, is the cause of the invisibility.

**4.2 The body is the feed**, chronological and day-grouped (`updates_day_groups.dart`). Its view control keeps **All / Unread** and loses **Needs you**, which moves to My Work with its meaning (§8).

**4.3 Triage is a fixed summary row above the feed**, never a scroll region, never an unbounded card:

- 0 pending → no row; the feed starts at the top.
- 1 pending → the row carries the Request title on one ellipsized line.
- 2+ pending → `N requests need your response` + stacked avatars.

**Tapping the row always opens the full-screen triage route**, at every count, carrying the Needs-me list with full card affordances, the `InboxSort` cycle (`inbox_screen.dart:424`), and scroll restoration. The Request detail stays reachable from the triage card, as today.

Rev 3 routed the single-item case straight to the Request detail. That stays withdrawn, but **rev 4's justification for withdrawing it was factually wrong and is replaced**.

Rev 4 argued that Inbox's two dismissal dialogs have different note audiences — private for `showInboxDismissDialog`, sent to the forwarder for `showRejectionDialog` — and that detail carries only the second. The copy does differ (`rejection_dialog.dart:72-89`), but the behaviour does not: both call `inboxCubit.reject(..., message: msg)` (`inbox_screen.dart:753-765`), both write the same `rejection_message` (`inbox_cubit.dart:285-289,336-339` → `inbox_set_status.graphql:8`), and a trigger copies it onto every matching forward edge as `recipient_rejection_message` (`m0015.dart:67-76`), which Hasura exposes to the sender (`hasura/metadata.json:1399-1407`). There is no private path to preserve. See §16.

The rule stands on **operational consistency** instead: one row, one destination, at every count. A tap that means "open triage" at two items and "open the Request" at one is a rule the user has to learn from experience. Detail's overflow does carry the affordances (`beacon_view_app_bar_overflow.dart:461-512`), so this is a coherence argument, not a capability one. Kimi's original objection — that a bare summary row withheld *which* Request was waiting — is answered by the title on the row, not by the destination.

Rev 2 made the row a bare summary at every count; that overcorrected, charging the overwhelmingly common single-item case two transitions to learn *which* Request is waiting. Rev 1's inline full card is still rejected: Inbox cards carry requirements, room hints, deadlines and an expandable sender-provenance fold (`inbox_item_tile.dart:205-220`, `inbox_card_forwards_fold.dart:28`) and are unbounded in height — the golden harness exercises 280–420 logical px (`inbox_item_tile_golden_test.dart:74,137`). One ellipsized title line is a bounded contract; a card is not.

Note the keyboard is *not* part of this argument: the home shell sets `resizeToAvoidBottomInset: false` (`home_screen.dart:196,270`), so the keyboard overlays content without changing any height contract. Text scaling and the expandable fold are the real constraints.

**4.4 Pinned prompts open the feed's scroll**, per §5. The scroll's sliver order is fixed: **pinned prompts → resolved tombstones → chronological day groups**.

**4.5 The resolved/tombstone section is the second sliver inside the feed's scroll, on the All view only, and is collapsed by default.** `closedBeforeResponse` and `deletedBeforeResponse` are genuine server transitions (`server/.../m0097.dart:55`) currently rendered as a dismissible 24h section inside the Needs-me tab's scroll (`inbox_state.dart:32-52`, `inbox_screen.dart:671-732`). It must not join the fixed chrome: at ~180–230dp per tombstone card it is unbounded and could push the feed off a compact screen entirely. Its dismissal rules and 24h window survive unchanged, and it renders independently of the pending count. A receipt is not a fallback for it — `relayReceived` is content-authorized (`server/.../attention_policy.dart:154`) and content-policy receipts vanish when content access fails (`server/.../m0117.dart:36`).

**4.6 The first-screen budget, measured.** Compact tokens: `appBarHeight: 56`, `bottomNavHeight: 64` (`tentura_tokens.dart:180-181`). On a 360×640 compact screen the scrollable region is roughly `640 − 56 − 64 − ~24 safe ≈ 496dp`.

At 1.3× text scale:

| element | cost |
|---|---|
| triage row (fixed) | ~52–60dp |
| view control All/Unread (fixed) | ~42–48dp |
| Watching affordance, if a second fixed row (§4.7) | ~52–60dp |
| pinned prompts, 3 × `UpdatesFeedTile` (in scroll) | ~280dp |
| one expanded tombstone card (in scroll) | ~234–300dp |

Fixed chrome alone is ~94–108dp, or ~146–168dp with a Watching row. Adding three pinned prompts and one expanded tombstone puts non-chronological content at ~514–580dp against ~328–388dp of remaining space — **the chronological feed would be entirely below the fold on first paint**, which defeats the document's purpose.

Binding consequences:

- pinned prompts cap at **2**, not 3 (§5.5 amended);
- the resolved section is **collapsed by default** (§4.5), expanding on tap;
- the Watching affordance must not be a second fixed row; §4.7 resolves it to a counted overflow entry;
- acceptance requires that at least one chronological receipt is visible on first paint at 360×640 and 1.3× with the worst-case combination above.

**4.7 Watching stays a reachable Request collection**, reached as a pushed route from the branch's overflow menu alongside Rejected (whose restore operation is preserved, `inbox_rejected_screen.dart:97`). It cannot become a receipt filter: `upsertWatchingForSender` fires after a forward when the sender has no active help offer (`forward_case.dart:263-272`) and on help-withdraw (`help_offer_case.dart:238-243`), so Watching is the passive accumulation surface of every active forwarder, while relay announcements explicitly exclude the sender (`server/.../attention_intent_case.dart:54`). No receipt filter can guarantee every watched Request appears, and a filter drops Stop watching, Forward, Dismiss and Offer help.

Watching is high-traffic — every active forwarder accumulates it — which argued for a body-level affordance. §4.6's budget rules out a second fixed row, and rev 4 resolves it as **a counted entry in the branch overflow, plus the forward-success intent of §7**.

Rev 4 justified this by claiming watched-Request activity "already flows into the feed as ordinary receipts", so nothing is lost. **That claim is withdrawn — it is only partly true.**

Watching status *is* consulted in recipient selection: `beacon_room_notification_context_repository.dart:53-59` reads Inbox status `[0,1]`, and `attention_intent_case.dart:791-823` adds those users as candidates for **`requestStatusChanged`**. So a watcher does hear about status transitions. But ordinary room activity resolves to *admitted members* (`beacon_notification_recipient_resolver.dart:194-200`), and Watching confers no content permission of its own (`m0162.dart:15-43` grants none; discoverability-derived access is open-family only). Watching-only status receipts are classified noisy / `requestProgress` (`attention_policy.dart:73-76,257-259`) and disappear entirely on content-permission loss or preference (`m0117.dart:39,55-63`).

So the feed covers a watcher who is also admitted, and covers status transitions for everyone. It does **not** cover a Watching-only, non-admitted user's view of room activity, and it can go silent on preference or permission change.

The overflow entry must therefore be specified as a genuine collection entry point, not a convenience: reachable without the post-forward snackbar, carrying a count, and listing Requests the feed may never mention. The snackbar intent (`forward_messages.dart:145-152`) remains the high-traffic path but is no longer the justification. Rev 5 owes an enumeration of the Watching-only, non-admitted, muted, and post-close cases and what each shows.

**4.8 Loading and failure are per-source.** Inbox already distinguishes an unloaded projection from a successful empty one (`inbox_state.dart:18-25`), and its current initial load can replace the whole body with a spinner (`inbox_screen.dart:169`). Here the triage row, the prompts and the feed load and fail independently: an unavailable pending count must never render as inbox-zero, and must never block an available feed.

## 5. Prompt-class rules

1. **Never counted in any badge.** Prompts arrive in bursts, refusal is free, and `skipped` is a legitimate outcome. Counting them reproduces the permanently-pinned-number failure of §6.
2. **Pinned above the chronological flow while `pending` and fresh.** A prompt is not "the newest event"; it is an open offer, and floating it is honest.
3. **Settling demotes it.** On `answer` or `skip` it drops to its chronological position as an ordinary history row.
4. **Staleness demotes it — client-side, display-only.** A prompt still `pending` after 7 days demotes to chronology, computed on the client from `receipt.createdAt`. It remains actionable in place; it simply stops holding the first screen once its value has decayed.

   The wire type carries only `inviterUserId, inviteeUserId, state, slugs` (`custom_types.dart:1010-1019`) and the table only adds `updatedAt`; there is no `staleAt`, and **none is being added**. Staleness changes no state, no count, and nothing the user can do — it reorders one row. Two devices disagreeing for a few hours about whether a prompt is still pinned costs nothing: the prompt is actionable in both. A schema column, migration and wire change to synchronise a cosmetic ordering decision is disproportionate.

   **What does differ between devices, stated precisely.** Rev 4 claimed staleness "changes no state, no count, and nothing the user can do". Domain state and the badge are indeed untouched, but the observable surface is not: with three prompts pending and one at the 7-day boundary, device A sees three fresh and pins two with an overflow row reading `N = 1`, while device B sees two fresh, pins both, and shows no overflow row at all (§5.5). The pinned pair itself can differ. Per-prompt actions remain available in both (`invite_accepted_receipt_card.dart:123-162`); it is the batch entry point that diverges.

   This is accepted, not overlooked: every prompt stays actionable on every device, and the divergence self-resolves as the boundary passes. What rev 5 owes is a definition of pin ordering, of the population `N` counts, and of when the boundary is recomputed — not a `staleAt` column.

   Accordingly, §5.7's convergence guarantee is scoped to **settle**, not staleness, and that is deliberate rather than a gap.
5. **Bounded.** At most **2** pinned (§4.6); beyond that, one collapsed row (`N people joined via your invites — set up access`) opening a batch sheet.

The card itself is unchanged: `InviteAcceptedReceiptCard` already puts the action on the row with a setup sheet, requiring no navigation. Only its position changes.

### 5.6 Edge cases

- **Blocked subject.** Already handled server-side: the intent emits no receipt when the viewer has blocked the subject (`attention_intent_case.dart:1111-1124`). No client rule needed.
- **Re-invite.** One row per invitee (§2.3), so a second inviter reuses it. The rule: an `upsert` that returns the row to `pending` re-arms the prompt for whoever the current `inviterUserId` is; it does not create a second pinned row.
- **Invitee deletion.** The prompt row is cleaned up with the user; a pinned prompt whose subject no longer resolves demotes immediately rather than rendering an empty card.
- **Cap unit.** §5.5's cap counts **receipts**, not invitees — one inviter inviting three people produces three receipts and three would-be pins.

### 5.7 The display contract, stated honestly

A pinned prompt is **lifted out of its chronological position** while `pending` and fresh, and **reinserted** on settle or staleness. It is not additionally rendered in place; rendering both would duplicate the row.

Rev 1's withdrawn mechanic (§13.1) is mechanically the same lift-out. What makes it sound here is narrower than rev 3 originally claimed, and the claim is corrected accordingly:

- **What §13.1 actually broke:** ordinary receipts have no settle state, so the client hid rows on its own authority, corrupting server-side unread accounting and diverging across devices.
- **What holds here:** the lift-out is *derived* from authoritative server state written through `answer`/`skip`, so it converges across devices, and **the unread total is untouched at every point**.
- **What does not hold, and is withdrawn:** the claim that no receipt is hidden from the feed. A lifted-out row is absent from its chronological position by construction. The honest statement is: *no receipt is hidden from the unread total; a prompt receipt is relocated within the feed while pending-and-fresh.*

Cursor pagination is unaffected: the cursor is generated from the server page boundary (`server/.../attention_repository.dart:142-146`) and prompt state is fetched separately, so relocation happens inside an already-fetched page.

**Implementation constraint.** `InviteAcceptedSetupPort.fetchPrompt(subjectId)` is per-subject (`invite_accepted_setup_case.dart:13`) and the card loads it lazily (`_PromptLoadPhase.loading`). Pinning requires prompt state **before** the feed renders, or rows will reorder after paint.

A static `pending` flag on the receipt payload does **not** suffice, and rev 4's claim that it was an equivalent option is withdrawn. Dispatch stores an event-time projection (`attention_dispatch_repository.dart:84-88,140-141,168`) and the feed read never joins prompt state (`attention_repository.dart:82-104`), while `answer`/`skip` write a different table entirely (`invite_seed_attestation_case.dart:63-95`, `invite_seed_prompt_repository.dart:66-101`). A frozen flag would therefore read `pending` forever. The existing card only refetches when the receipt id or payload changes (`invite_accepted_receipt_card.dart:68-77`), so a batch fetch alone inherits the same staleness.

What is required is either a **read-time prompt-state projection** joined into the feed query, or a batch fetch **plus an explicit invalidation and refetch contract**. Either way the acceptance case is: skip a prompt on device A, and device B — where the receipt is already seen — demotes it without a cold restart. Authoritative storage alone does not prove convergence.

## 6. Badges

One indicator per destination, two states, priority-ordered.

**Activity:**
- pending triage items > 0 → **numeric badge**, the count of Inbox `needsMe` rows;
- else unread > 0 → **dot**;
- never both.

The number is bounded by the triage lifecycle (`inbox_set_status`) rather than accumulating indefinitely. It is not monotonically decaying: restore-rejected returns an item to `needsMe` and increments it (`inbox_cubit.dart:293-296`). A prompt never contributes; a `pending` prompt that the user has already seen produces no signal, by design — the pinned position is the reminder. **The badge reports arrival; placement reports openness.**

**My Work:** the numeric badge counts live obligations, and requires §9 first.

Both states carry distinct accessible descriptions ("3 requests need your response" vs. "new activity"). The dot-vs-number distinction is the second channel and is already the M3 `Badge` small/large dichotomy.

**Why rev 2's formula is withdrawn.** It summed pending triage items and `needsYouTotal`. But `needs_you_total` is computed as `COUNT(*) FILTER (WHERE requires_action AND settlement_kind IS NULL)` with **no `seen_at IS NULL` filter**, while `unread_total` beside it does filter on `seen_at` (`server/.../attention_repository.dart:89-95`). Settlement is a manual gesture nothing else performs — triaging an Inbox item does not settle receipts, and reading one does not settle it. The badge would therefore converge on a permanent number equal to the user's lifetime count of unsettled obligations, training users to ignore the one signal this document exists to make meaningful.

Moving obligations to My Work removes that defect from Activity's critical path. It does not fix it; §9 does.

## 7. Navigation contracts

Each entry path is specified separately. Rev 2's "opening shows the feed, always" collided with existing behaviour.

- **Cold start / deep link.** `/home/updates` → `/home/inbox?tab=receipts` (`root_router.dart:177-182`) and `/notifications` chaining through it keep working and land on the feed. Notification-open intents constructing the Receipts destination (`root_router.dart:553`) keep working. Only `'receipts'` was ever a recognised `tab` value (`inbox_screen.dart:56-57`, `consts.dart:62-63`), so URL breakage is minimal.
- **Branch return.** Restores the last view, scroll offset and search text. Feed views own scroll keys (`updates_feed_pane.dart:177-178`); the keep-alive / page-storage machinery (`inbox_screen.dart:369`) is re-pointed, not deleted.
- **Reselect.** Scrolls the feed to top and clears search. Full stop. Rev 2 proposed a "second reselect opens triage" gesture; withdrawn — `HomeTabReselectCubit` is a pure counter (`home_tab_reselect_cubit.dart:14-28`), a temporal double-gesture has no precedent, no discoverability and no accessibility mapping, and triage is already reachable from an always-visible row.
- **Forward-success intent.** `requestInboxWatching(beaconId)` from the forward snackbar (`forward_messages.dart:145-152`) currently animates to the Watching tab (`inbox_screen.dart:84-94,119-124`). With Watching demoted to a pushed route this intent must be explicitly re-pointed to that route, scrolled to the named Request. **This is a hard requirement, not a detail:** it is the feedback edge of the forwarding loop.
- **Return from triage or Request detail.** Restores feed position.

## 8. What My Work must gain

This proposal is two changes, not one. Activity cannot shed obligations unless My Work accepts them.

- The **Needs you** view moves to My Work with its meaning intact, backed by `AttentionView.needsYou`.
- My Work's badge becomes a numeric obligation count. Today `hasMyWorkDot` is the intersection of `myWorkBeaconIds` with unread beacon ids (`home_attention_state.dart:49`) — "something is new in your Requests", with no distinction between a chat message and a help offer.
- The overlap rule ("My Work wins", `home_attention_state.dart:29-30`) is preserved and becomes semantically correct rather than incidental: obligations were always My Work's.

**8.1 My Work's scope gains an obligation set — and this is server work.** Today the scope is authored non-archived Requests plus help offers with `status: {_eq: 0}` (`my_work_fetch.graphql:6-23`, archive exclusions at `:10,22`), and the whole path — `my_work_repository.dart:41-54` → `my_work_case.dart:114-124` → `derive_my_work_cards.dart:199-212` — handles exactly those two sets. The rule it gains:

> **Any Request carrying a live obligation for the viewer is in My Work's scope, regardless of archive state or help-offer status.**

This is deliberately broader than the `reviewOpened` → `formerCommitter` hole that motivated it (§2.2). The same hole exists for an author who archived their own Request and then received a help offer: `authoredNonArchived` excludes it while the obligation is real. Archive is a display preference over the user's own work list; a live obligation with a counterparty outranks it. When the obligation settles, the Request leaves the obligation set and reverts to whatever the other two sets say about it.

**Rev 4 asserted this as a client-side scope edit. That was wrong and is withdrawn.** "Carries a live obligation" is a predicate over authorized rows in `notification_outbox` (`attention_repository.dart:82-104`). That table is **not registered in Hasura metadata at all**, so no amount of condition-adding to My Work's existing GraphQL can express it. Beacon reads additionally require `can_read_content` (`hasura/metadata.json:274-277`), and holding an obligation does not confer read permission.

§8.1 therefore requires the server contract in §9.1, and My Work requires:

- a **third input** alongside authored and help-offered — the beacon-id set returned by that contract;
- **card derivation** for a Request present only via that set (it may be archived, or carry no active offer, so the existing card builders have no row to hang on);
- **refresh triggers** — the set changes when an obligation arrives, settles, or expires, none of which are events My Work listens to today.

Rev 4's claim that global and scoped counts "coincide by construction" is withdrawn as a pre-implementation assertion. The construction argument only holds once §9.1 and §9.3 both ship, and it must then be asserted by a test (§9.6).

## 9. Server changes required

Rev 4 claimed two items, neither on Activity's critical path. The rev 4 review disproved both halves of that: there are six, and one of them (§9.4) is on Activity's critical path.

| # | item | serves | blocks |
|---|---|---|---|
| 9.1 | live-obligation beacon-id contract | §8.1, §9.6 | My Work scope + badge |
| 9.2 | `expired` settlement kind: constraint, parser, writer | §9.3 | My Work badge accuracy |
| 9.3 | expiry settlement at review-window close, plus backfill | §6, §9.6 | My Work badge accuracy |
| 9.4 | prompt-state read-time projection or batch + invalidation | §5 | **Activity** |
| 9.5 | unseen-live-obligation aggregate | §6 | My Work badge |
| 9.6 | scope/count coincidence test | §8.1 | My Work badge |

**9.1 Live-obligation beacon-id contract.** A query returning the authorized set of beacon ids for which the viewer holds a live obligation — symmetric to `unreadForBeacons` (`attention_repository.dart:24-48`) and sharing its authorization path so the two cannot diverge. This is the prerequisite §8.1 depends on.

**9.2 The `expired` settlement kind cannot simply be written.** The CHECK constraint admits only `resolved, dismissed, superseded, legacy_archived` (`m0118.dart:15-18`), so the UPDATE fails outright. Beyond the migration, `attention_models.dart:147-160` is a closed enum parsed with `firstWhere` and `attention_repository.dart:203-207` converts on read, so an old server instance reading an `expired` receipt throws. Required, in this order:

1. CHECK migration admitting `expired`;
2. server enum and parser accepting it;
3. deploy so that no old reader remains;
4. only then enable the writer.

The writer is a **system** settlement path, not the user one — `attention_settlement_case.dart:26-28` is limited to two user-driven values. It must set `settled_at` alongside the kind (the `settlement_facts_chk` constraint requires it) and must preserve existing `seen_at` / `read_at`. A receipt already marked seen is still in scope: seen is not settled.

**9.3 Expiry settlement at review-window close.** Rev 4 speculated the window might close lazily with no event to hang this on. That was wrong: `task_worker_case.dart:191-199` sweeps every minute, `evaluation_case.dart:144-145` invokes the same sweep, and `attention_expiry_sweep_case.dart:33-48` → `review_finalization_case.dart:73-99` is the real transaction boundary. Settlement belongs inside that transaction.

Two gaps the hook alone does not close:

- **Backfill.** The sweep only visits `status = 0` (`attention_expiry_repository.dart:19-23`) and the finalizer stops at `evaluation_repository.dart:663-664`, so windows already closed before this ships are never revisited. Their obligations would persist forever — and under §8.1 would pin their Requests into My Work permanently. A one-time backfill is required, not optional.
- **Reopen.** `evaluation_case.dart:445-455` deletes review scaffolding and returns the Request to Open, removing the expiry target itself. Reopen must settle outstanding obligations as `superseded`.

Distinguish the outcomes: submitted → `resolved`; window closed unsubmitted → `expired`; reopened → `superseded`. Verify against both seen and unseen receipts.

**9.4 Prompt-state convergence** — see §5's implementation constraint. Either a read-time projection joined into the feed read, or batch fetch plus an invalidation/refetch contract. **This is on Activity's critical path**, unlike everything else in this section: without it §5's pinning either never demotes or demotes only after a cold restart.

**9.5 Unseen-live-obligation aggregate.** `needs_you_total` is `COUNT(*) FILTER (WHERE requires_action AND settlement_kind IS NULL)` with no `seen_at IS NULL` filter, while `unread_total` beside it does filter on `seen_at` (`attention_repository.dart:89-95`). Either add a counter that filters on unseen, or rely on §9.3's expiry to make the existing one decay. Both is better.

**9.6 The coincidence test.** Once §9.1 and §9.3 ship, every live obligation implies scope membership and every scope-exit implies settlement, so global and scoped counts coincide. That must be asserted by a test rather than assumed — rev 3 and rev 4 both asserted it prematurely on different grounds and were both wrong.

## 10. Cleanup: retired coordination machinery

Ask, Blocker and Promise are retired in `DiscussionProductPolicy.retiredCoordinationKinds`; Plan is retired by product decision, leaving `supportedCoordinationKinds` empty in practice. The following are dead and are to be removed as a distinct, separately reviewable change:

- server use cases under `domain/use_case/coordination_item/` (`publish_draft_ask_case`, `mark_ask_case`, `accept_ask_case`, `resolve_ask_case`, `accept_promise_case`, `resolve_promise_case`, `publish_draft_blocker_case`, `mark_blocker_case`, `resolve_blocker_case`, `remind_coordination_item_case`, `update_coordination_item_case`), their DI registrations, and `api/controllers/graphql/mutation/mutation_coordination_item.dart`;
- the `AttentionIntentCase` methods with no surviving caller: `needsMe`, `staleReminder`, `blockerChanged`, `commitmentChanged`, and the `commitmentRedirected` / `blockerOpened` branches of `AttentionPolicy._requiresAction`;
- the client `features/coordination_item/` feature, including `coordination_item_overflow_menu.dart:276` → `item_actions_cubit.dart:136` → `remindItem`, which is the only live wire into `staleReminder`;
- the glossary entry for **Plan (coordination item)** in `CONTEXT.md` §Language, which still describes it as a live structured object on an Items tab.

**Sequencing constraint: the NOW line is currently implemented on this substrate.** Editing NOW runs client `room_cubit.updatePlan` (`beacon_threads/ui/bloc/room_cubit.dart:738`) → `beacon_threads_case.dart:315` → `CoordinationItemCase.updatePlan` (`features/coordination_item/domain/use_case/coordination_item_case.dart:203`) → server `UpdatePlanCase`, which calls `publishRootPlan(..., syncCurrentLineText: trimmed)` and emits `coordinationChanged` (`update_plan_case.dart:65-82`). So NOW is a root `kindPlan` coordination item whose text is synced onto `BeaconRoomState`. Conceptually distinct, mechanically not separable as written.

Removal therefore proceeds in two steps, in this order:

1. **Re-seat the NOW line** directly on `BeaconRoomState` with its own mutation and use case, retiring `UpdatePlanCase`, `publishRootPlan`, and the client `updatePlan` chain. Decide whether NOW edits keep emitting `coordinationChanged` receipts or gain their own event type.
2. **Only then** remove the use cases, mutation and client feature listed above.

Reversing this order breaks a live product surface. `add_plan_step_case.dart` and the rest of the plan-step family have no surviving product surface and go in step 2.

Persisted kind codes are never renumbered (`DiscussionProductPolicy`), and existing rows are left in place. Step 2 is a code and surface removal; step 1 is a data-path change and needs its own migration decision for existing root plan rows.

## 11. Migration and test blast radius

**Integration.** `offerHelpFromInbox` and `openRequestFromInbox` (`integration_test/support/e2e_test_helpers.dart:588-638`) navigate to `kPathInbox` and expect Needs-me cards in the body. Nine lifecycle specs consume them: `request_lifecycle_closed_to_archive_test.dart:52`, `request_threads_navigation_test.dart:79`, `tab_attention_forced_background_test.dart:52`, `request_lifecycle_offer_admit_chat_test.dart:40`, `request_detail_back_navigation_web_test.dart:39`, `witness_admission_forward_band_test.dart:39`, `request_lifecycle_close_review_test.dart:31`, `request_lifecycle_review_trust_control_test.dart:20`, `request_lifecycle_create_forward_inbox_test.dart:31`. The helpers gain a `goToInboxTriage()` step rather than each spec being rewritten.

**Unit / widget.** `inbox_expanded_chrome_test.dart` (3 × `find.byType(TenturaPrimaryTabBar)`), `home_tab_branch_routing_test.dart:324-337`, `home_tab_reselect_cubit_test.dart` (2 cases), `inbox_receipts_fold_test.dart:146-153`.

**Also affected, by section:**

- §4.5 (tombstones move into the feed) — `inbox_case_test.dart:100-109` (`dismissTombstone`); decide whether dismissal stays on `InboxCubit`.
- §5 (prompt pinning) — `updates_feed_cubit_test.dart`: the cubit has no prompt handling today, so this is new coverage, not a fix. `invite_accepted_receipt_card_test.dart`: the "prompt state before feed render" constraint changes the card's lazy `_PromptLoadPhase.loading` contract (`invite_accepted_receipt_card.dart:80-90`).
- §8/§8.1 (My Work gains obligations and review-window scope) — `my_work_load_review_windows_test.dart:50-61` asserts `canCloseNow` for authored Requests only, and the ~17 `my_work_*_test.dart` files carry no obligation coverage at all. Rev 3 listed none of these.
- §6 (Activity badge becomes a triage count) — `inbox_navbar_item.dart` renders the badge and is inside the `shell_counters` contract bucket (`realtime_entity_contract_impacts_test.dart:107-111`) alongside `inbox_receipts_tab_label.dart`.

**Contracts.** The `updates-unread-count-$unread` semantics identifier (`inbox_receipts_tab_label.dart:25`) is pinned by `realtime_entity_contract_impacts_test.dart:108-116` and must be re-homed, not deleted. Note also that the `updates-needs-you` tab id (`updates_feed_pane.dart:157`) and `AttentionView.needsYou` leave the Activity feed with **no** pinning test covering the 3-tab → 2-tab change — an absence of coverage rather than a breakage, but one rev 4 should close.

## 12. Terminology

**Activity** / «Активность» is a new user-facing product noun and must be added to `CONTEXT.md` §Terminology before use, with `scripts/check-user-facing-terminology.sh` updated accordingly. Internal identifiers stay `inbox`. The change also carries the mandatory version bump and `web/index.html` cache-buster sync.

## 13. Withdrawn from earlier revisions

1. **Deduplication of pending forward receipts / "settles into history" for receipts generally.** Withdrawn in rev 2 and still withdrawn. Unread totals count the whole authorised visible set server-side (`attention_repository.dart:88`) and "read all" acknowledges that same set (`:353`), so a client-side hidden receipt either keeps contributing unread attention or is marked seen invisibly. Inbox and attention arrive over separate realtime subscriptions (`inbox_case.dart:55`, `updates_feed_cubit.dart:21`), so there is no atomic cross-device move; and triage is reversible. The mechanic returns in §5 for prompts only, where server-side settle state makes it sound.
2. **"You accepted X's request" as a history event.** No such transition exists (§2.1); `inbox_set_status` records status and rejection text only.
3. **Watching as a filter chip** (§4.7).
4. **"All / Watching / Mentions" filter axis.** The feed already has All / Unread / Needs you backed by `AttentionView`, and no mention predicate exists in the receipt model.
5. **The inline full pending card** (§4.3) — and, from rev 2, the bare summary row at count 1.
6. **"Unread updates never light the navbar."** Corrected to a coverage gap (§1.1).
7. **The badge formula `needsMe + needsYouTotal`** (§6).
8. **"Second reselect opens triage"** (§7).
9. **"Five destinations plus a command button."** There are five destinations total; Constellation is one of them and merely receives command-style chrome (`home_screen.dart:282`, `home_bottom_navigation_bar.dart:101`).

Withdrawn from revision 3:

10. **"No receipt is hidden from the feed."** A pinned prompt is lifted out of its chronological position by construction; the accurate guarantee is about the unread total only (§5.7).
11. **Routing a single pending triage item to the Request detail.** Loses the private "Remove from inbox" dismissal path (§4.3).
12. **A `staleAt` column for prompt staleness.** Staleness is display-only; the column is disproportionate (§5.4).
13. **Three pinned prompts, and an expanded-by-default resolved section.** Both violate the measured first-screen budget (§4.6).

Withdrawn from revision 4:

14. **§8.1 as a client-side scope edit.** `notification_outbox` is not in Hasura metadata; the predicate is unreachable from My Work's GraphQL (§8.1, §9.1).
15. **"Coincidence by construction" as a pre-implementation argument.** It holds only after §9.1 and §9.3 ship, and must be test-asserted (§9.6).
16. **The private-vs-forwarder dismissal justification.** Both dialogs write the same field, and the trigger exposes it to the sender (§4.3, §16).
17. **"A payload `pending` flag is an equivalent option."** A frozen event-time projection reads `pending` forever (§5).
18. **"Watching's seeing job is already fully served by the feed."** True only for admitted watchers and status transitions (§4.7).
19. **"Neither server item is on Activity's critical path."** §9.4 is.

## 14. Open questions

Owed by revision 6, and named at their sections:

1. **Pin ordering, the population `N` counts, and boundary recomputation** for prompts (§5.4).
2. **The Watching case enumeration** — Watching-only, non-admitted, muted, post-close (§4.7).
3. **The invalidation/refetch contract** for prompt state (§5, §9.4).

Genuinely optional or later:

4. **The 7-day prompt staleness window** (§5.4) is a guess. Display-only and client-side, so it is cheap to change and safe to ship wrong.
5. **Whether `mutual_connection_formed` becomes the second prompt-class member** (§2.3). Out of scope; §5's rules accept it without a fourth mechanic.
6. **Whether NOW-line edits keep emitting `coordinationChanged`** after §10 step 1, or gain a dedicated event type.

## 15. Review status

| pass | reviewer | verdict |
|---|---|---|
| rev 1 | codex / Astra (GPT-6) | reject as written |
| rev 2 | cursor-agent / Kimi K3 High | REJECT (spine sound) |
| rev 3 | codex / Astra | incomplete — budget exhausted at ~108k tokens; 2 findings recovered from the trace |
| rev 3 | cursor-agent / GLM 5.2 High | ADOPT WITH CHANGES |
| rev 4 | codex / Astra | **REJECT** — 1 blocking, 5 major |
| rev 5 | — | not yet reviewed |

Across five passes the **spine has never been contested**: the feed as the branch body, triage as a bounded summary above it, obligations belonging to My Work, Watching as a Request collection, prompts placed rather than counted. Every rejection has been of a supporting mechanic or a justification, and in three cases of a factual claim about the codebase that turned out to be false.

The rev 4 pass was the most damaging so far, because it invalidated reasoning rather than detail:

- **§8.1 was declared, not designed.** `notification_outbox` is absent from Hasura metadata, so the invariant is a server contract (§9.1). Rev 4's "coincidence by construction" rested on it and fell with it.
- **§4.3's justification was inverted.** The "private" dismissal note is exposed to the forwarder (§16). The conclusion survived on different grounds; the reasoning did not.
- **§9.3's premise was wrong in the document's favour.** Rev 4 speculated review windows might close lazily with no hook. There is a per-minute sweep — but it never revisits already-closed windows, so a backfill is mandatory.
- **§4.7 and §5's payload option** both rested on claims that were true only in part.

Rev 5 changes no product decision and no layout. It corrects four justifications, converts §9 from two optional items into six with a dependency table, and records §16.

## 16. Out of scope: a shipped privacy defect

Found while verifying §4.3. Recorded here because this document must not silently depend on it, and because it should be fixed independently of anything proposed above.

`showInboxDismissDialog` presents the hint **"Optional note (only you see this)"** (l10n `inboxDismissDialogHint`). The note is not private. Both dismissal dialogs call `inboxCubit.reject(..., message: msg)` (`inbox_screen.dart:753-765`), which writes `rejection_message` on `inbox_item` (`inbox_cubit.dart:285-289,336-339` → `inbox_set_status.graphql:8`). The trigger `inbox_item_on_rejection_update` copies it to `beacon_forward_edge.recipient_rejection_message` for every matching edge (`m0015.dart:67-76`), and Hasura's `user` role may select that column where `sender_id` matches the viewer (`hasura/metadata.json:1399-1407`).

So a note written under a promise of privacy is readable by the person who forwarded the Request.

**Status: copy corrected as a stopgap; behaviour tracked in [#137](https://github.com/Intersubjective/tentura/issues/137).** `inboxDismissDialogHint` now reads "Optional note — the sender will see it" / «Комментарий необязателен — его увидит отправитель» (`ba3a45905`), so the interface no longer promises what it does not deliver.

**The product decision is that the note must be private.** It therefore needs its own column and permission rather than a share of `rejection_message`, with the dismissal trigger never reading it — see #137, which also records that existing rows cannot be retroactively attributed to one dialog or the other, since both set `status = 2` and write the same column.

One consequence worth carrying forward: once #137 lands, the two dialogs differ in **substance**, not only wording — "remove from my inbox" becomes private and "can't help" stays communicated. §4.3 was rewritten in rev 5 to rest on operational consistency rather than on that distinction, and it stays that way; the distinction returning is a reason the rule is comfortable, not a reason to revisit it.
