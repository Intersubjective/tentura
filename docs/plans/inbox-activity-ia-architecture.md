# Inbox → Activity: information architecture — architectural proposal

Status: architectural proposal, revision 7. Not an implementation plan. No application, API, schema, or data changes are authorized by this document alone.

Date: 2026-09-10. Repository baseline inspected: `c6b24012d`, plus this branch.

Revisions 1–6 went through seven independent adversarial review passes (§12), six of which produced findings. Mechanics withdrawn under them are listed in §10 so they are not silently reintroduced.

**Revision 6 splits the document.** Server contracts, migration ordering, shipping sequence and test blast radius have moved to [`inbox-activity-ia-implementation-plan.md`](inbox-activity-ia-implementation-plan.md). Six passes had pushed every surviving objection into precisely that material — including a blocking finding about shipping order — which a document declaring itself "not an implementation plan" was never scoped to carry. What remains here is the part that has never been contested: which objects exist, where they belong, and how the surface behaves. User-facing **Request** remains internal **Beacon**; this proposal adds no parallel entity, table, or route family.

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

Dead producers, retained only by DI and tests: `needsMe` (only `publish_draft_ask_case.dart:83` and `mark_ask_case.dart:83`), `staleReminder` (only `remind_coordination_item_case.dart:92`, which rejects retired kinds), `blockerOpened` and `commitmentRedirected` (retired kinds only). See the implementation plan §4.

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
| Obligations (§2.2) | **My Work** | numeric badge (implementation plan §2.5, step 7) |
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

Rev 4 argued that Inbox's two dismissal dialogs have different note audiences — private for `showInboxDismissDialog`, sent to the forwarder for `showRejectionDialog` — and that detail carries only the second. The copy does differ (`rejection_dialog.dart:72-89`), but the behaviour does not: both call `inboxCubit.reject(..., message: msg)` (`inbox_screen.dart:753-765`), both write the same `rejection_message` (`inbox_cubit.dart:285-289,336-339` → `inbox_set_status.graphql:8`), and a trigger copies it onto every matching forward edge as `recipient_rejection_message` (`m0015.dart:67-76`), which Hasura exposes to the sender (`hasura/metadata.json:1399-1407`). There is no private path to preserve. See §13.

The rule stands on **operational consistency** instead: one row, one destination, at every count. A tap that means "open triage" at two items and "open the Request" at one is a rule the user has to learn from experience. Detail's overflow does carry the affordances (`beacon_view_app_bar_overflow.dart:461-512`), so this is a coherence argument, not a capability one. Kimi's original objection — that a bare summary row withheld *which* Request was waiting — is answered by the title on the row, not by the destination.

Rev 2 made the row a bare summary at every count; that overcorrected, charging the overwhelmingly common single-item case two transitions to learn *which* Request is waiting. Rev 1's inline full card is still rejected: Inbox cards carry requirements, room hints, deadlines and an expandable sender-provenance fold (`inbox_item_tile.dart:205-220`, `inbox_card_forwards_fold.dart:28`) and are unbounded in height — the golden harness exercises 280–420 logical px (`inbox_item_tile_golden_test.dart:74,137`). One ellipsized title line is a bounded contract; a card is not.

Note the keyboard is *not* part of this argument: the home shell sets `resizeToAvoidBottomInset: false` (`home_screen.dart:196,270`), so the keyboard overlays content without changing any height contract. Text scaling and the expandable fold are the real constraints.

**4.4 Pinned prompts open the feed's scroll**, per §5. The scroll's sliver order is fixed: **pinned prompts → resolved tombstones → chronological day groups**.

**4.5 The resolved/tombstone section is the second sliver inside the feed's scroll, on the All view only, and is collapsed by default.** `closedBeforeResponse` and `deletedBeforeResponse` are genuine server transitions (`server/.../m0097.dart:55`) currently rendered as a dismissible 24h section inside the Needs-me tab's scroll (`inbox_state.dart:32-52`, `inbox_screen.dart:671-732`). It must not join the fixed chrome: at ~180–230dp per tombstone card it is unbounded and could push the feed off a compact screen entirely. Its dismissal rules and 24h window survive unchanged, and it renders independently of the pending count. A receipt is not a fallback for it — `relayReceived` is content-authorized (`server/.../attention_policy.dart:154`) and content-policy receipts vanish when content access fails (`server/.../m0117.dart:36`).

**4.6 The first-screen budget, measured.** Compact tokens: `appBarHeight: 56`, `bottomNavHeight: 64` (`tentura_tokens.dart:180-181`). On a 360×640 compact screen the scrollable region is roughly `640 − 56 − 64 − ~24 safe ≈ 496dp`.

At 1.3× text scale — this table is the calculation that *produced* the caps below, so two of its rows describe options this document then rejected:

| element | cost |
|---|---|
| triage row (fixed) | ~52–60dp |
| view control All/Unread (fixed) | ~42–48dp |
| Watching affordance, *had* it been a second fixed row — rejected below | ~52–60dp |
| pinned prompts at the originally proposed 3 × `UpdatesFeedTile` — capped at 2, and mutually exclusive with the collapsed row, below | ~280dp |
| one expanded tombstone card (in scroll) | ~234–300dp |

Fixed chrome alone is ~94–108dp, or ~146–168dp with a Watching row. Adding three pinned prompts and one expanded tombstone puts non-chronological content at ~514–580dp against ~328–388dp of remaining space — **the chronological feed would be entirely below the fold on first paint**, which defeats the document's purpose.

Binding consequences:

- pinned prompts cap at **2**, not 3, and three or more collapse to a single row instead of pinning alongside one (§5.5);
- the resolved section is **collapsed by default** (§4.5), expanding on tap;
- the Watching affordance must not be a second fixed row; §4.7 resolves it to a counted overflow entry;
- acceptance requires that at 360×640 and 1.3×, with the worst-case combination above, the branch honours §5.7's first-paint rule: if the fetched page holds any chronological row, one is visible without scrolling.

**4.7 Watching stays a reachable Request collection**, reached as a pushed route from the branch's overflow menu alongside Rejected (whose restore operation is preserved, `inbox_rejected_screen.dart:97`). It cannot become a receipt filter: `upsertWatchingForSender` fires after a forward when the sender has no active help offer (`forward_case.dart:263-272`) and on help-withdraw (`help_offer_case.dart:238-243`), so Watching is the passive accumulation surface of every active forwarder, while relay announcements explicitly exclude the sender (`server/.../attention_intent_case.dart:54`). No receipt filter can guarantee every watched Request appears, and a filter drops Stop watching, Forward, Dismiss and Offer help.

Watching is high-traffic — every active forwarder accumulates it — which argued for a body-level affordance. §4.6's budget rules out a second fixed row, and rev 4 resolves it as **a counted entry in the branch overflow, plus the forward-success intent of §7**.

Rev 4 justified this by claiming watched-Request activity "already flows into the feed as ordinary receipts", so nothing is lost. **That claim is withdrawn — it is only partly true.**

Watching status *is* consulted in recipient selection: `beacon_room_notification_context_repository.dart:53-59` reads Inbox status `[0,1]`, and `attention_intent_case.dart:791-823` adds those users as candidates for **`requestStatusChanged`**. So a watcher does hear about status transitions. But ordinary room activity resolves to *admitted members* (`beacon_notification_recipient_resolver.dart:194-200`), and Watching confers no content permission of its own (`m0162.dart:15-43` grants none; discoverability-derived access is open-family only). Watching-only status receipts are classified noisy / `requestProgress` (`attention_policy.dart:73-76,257-259`) and disappear entirely on content-permission loss or preference (`m0117.dart:39,55-63`).

So the feed covers a watcher who is also admitted, and covers status transitions for everyone. It does **not** cover a Watching-only, non-admitted user's view of room activity, and it can go silent on preference or permission change.

The overflow entry must therefore be specified as a genuine collection entry point, not a convenience: reachable without the post-forward snackbar, carrying a count, and listing Requests the feed may never mention. The snackbar intent (`forward_messages.dart:145-152`) remains the high-traffic path but is no longer the justification. **The collection is derived from Inbox rows, never from receipts.** That single rule settles the cases the feed cannot cover:

| case | what the collection shows |
|---|---|
| watcher who is also admitted | the Request, plus the room reachable as today |
| Watching-only, not admitted | the Request with title, author and its last known status transition — no room content, because none is authorized |
| notifications muted, or preference-suppressed | the Request, unchanged. Preferences filter receipts; they do not filter Inbox rows, which is exactly why the collection must not be receipt-derived |
| Request closed or gone quiet | the Request with its terminal status, until the viewer stops watching or the tombstone rules of §4.5 apply |

Each row carries Stop watching, Forward, Dismiss and Offer help, as today (`inbox_screen.dart:839-859`). A Request never silently disappears from this list because of a permission or preference change — only the viewer's own Stop watching, or the Request's lifecycle, removes it.

**4.8 Loading and failure are per-source.** Inbox already distinguishes an unloaded projection from a successful empty one (`inbox_state.dart:18-25`), and its current initial load can replace the whole body with a spinner (`inbox_screen.dart:169`). Here the triage row, the prompts and the feed load and fail independently: an unavailable pending count must never render as inbox-zero, and must never block an available feed.

## 5. Prompt-class rules

1. **Never counted in any badge.** Prompts arrive in bursts, refusal is free, and `skipped` is a legitimate outcome. Counting them reproduces the permanently-pinned-number failure of §6.
2. **Pinned above the chronological flow while `pending` and fresh.** A prompt is not "the newest event"; it is an open offer, and floating it is honest.
3. **Settling demotes it.** On `answer` or `skip` it drops to its chronological position as an ordinary history row.
4. **Staleness demotes it — client-side, display-only.** A prompt still `pending` after 7 days demotes to chronology, computed on the client from `receipt.createdAt`. It remains actionable in place; it simply stops holding the first screen once its value has decayed.

   The wire type carries only `inviterUserId, inviteeUserId, state, slugs` (`custom_types.dart:1010-1019`) and the table only adds `updatedAt`; there is no `staleAt`, and **none is being added**. Staleness changes no state, no count, and nothing the user can do — it reorders one row. Two devices disagreeing for a few hours about whether a prompt is still pinned costs nothing: the prompt is actionable in both. A schema column, migration and wire change to synchronise a cosmetic ordering decision is disproportionate.

   **What does differ between devices, stated precisely.** Rev 4 claimed staleness "changes no state, no count, and nothing the user can do". Domain state and the badge are indeed untouched, but the observable surface is not: with three prompts pending and one at the 7-day boundary, device A sees three fresh and pins two with an overflow row reading `N = 1`, while device B sees two fresh, pins both, and shows no overflow row at all (§5.5). The pinned pair itself can differ. Per-prompt actions remain available in both (`invite_accepted_receipt_card.dart:123-162`); it is the batch entry point that diverges.

   This is accepted, not overlooked: every prompt stays actionable on every device, and the divergence self-resolves as the boundary passes. What is owed is a definition of pin ordering, of the population `N` counts, and of when the boundary is recomputed — all three settled in §5.5.1 — not a `staleAt` column.

   Accordingly, §5.7's convergence guarantee is scoped to **settle**, not staleness, and that is deliberate rather than a gap.
5. **Bounded, and the two modes are exclusive.** One or two fresh pending prompts render as pinned rows. **Three or more render as a single collapsed row instead** — `N people joined via your invites — set up access` — opening a batch sheet; no individual prompt is pinned alongside it.

   Rev 5 left this ambiguous, and "2 pinned plus an overflow row" is the reading to avoid: it consumes the most vertical space of any option while showing the least, and it makes `N` mean "the ones you cannot see", which is a quantity nobody can act on. Either you see the prompts or you see their count.

### 5.5.1 Pin ordering, `N`, and the staleness boundary

- **Ordering.** Pinned prompts sort by `receipt.createdAt` descending — newest first, matching the feed around them. No secondary key is needed: the prompt table is keyed per invitee (§2.3), so two rows cannot share a subject.
- **Population of `N`.** `N` counts **all** fresh pending prompts, not an overflow remainder, which follows from the two modes being exclusive. Three fresh prompts read `3 people joined…`, not `1 more`.
- **Boundary recomputation.** Freshness is evaluated when the feed is built and on app resume — not on a timer. A prompt crossing the 7-day line while the user is looking at it does not rearrange the screen under them; it demotes the next time the feed is built. This bounds the cross-device divergence of §5.4 to "until one of them rebuilds", and makes the divergence a display race rather than a state disagreement.

The card's **presentation** is unchanged: `InviteAcceptedReceiptCard` already puts the action on the row with a setup sheet, requiring no navigation, and that stays. Its **data path** does change — placement and the card's own action must read one shared prompt projection, or a row can be demoted while the action mounted on it still offers a stale choice. Rev 6 said "the card itself is unchanged"; that was wrong about the data path and is corrected here. Mechanism and acceptance live in the implementation plan §2.4.

### 5.6 Edge cases

- **Blocked subject.** Already handled server-side: the intent emits no receipt when the viewer has blocked the subject (`attention_intent_case.dart:1111-1124`). No client rule needed.
- **Re-invite.** One row per invitee (§2.3), so a second inviter reuses it. The rule: an `upsert` that returns the row to `pending` re-arms the prompt for whoever the current `inviterUserId` is; it does not create a second pinned row.
- **Invitee deletion.** The prompt row is cleaned up with the user; a pinned prompt whose subject no longer resolves demotes immediately rather than rendering an empty card.
- **Cap unit.** §5.5's cap counts **receipts**, not invitees — one inviter inviting three people produces three receipts and three would-be pins.

### 5.7 The display contract, stated honestly

A pinned prompt is **lifted out of its chronological position** while `pending` and fresh, and **reinserted** on settle or staleness. It is not additionally rendered in place; rendering both would duplicate the row.

Rev 1's withdrawn mechanic (§10.1) is mechanically the same lift-out. What makes it sound here is narrower than rev 3 originally claimed, and the claim is corrected accordingly:

- **What §10.1 actually broke:** ordinary receipts have no settle state, so the client hid rows on its own authority, corrupting server-side unread accounting and diverging across devices.
- **What holds here:** the lift-out is *derived* from authoritative server state written through `answer`/`skip`, so it converges across devices, and **the unread total is untouched at every point**.
- **What does not hold, and is withdrawn:** the claim that no receipt is hidden from the feed. A lifted-out row is absent from its chronological position by construction. The honest statement is: *no receipt is hidden from the unread total; a prompt receipt is relocated within the feed while pending-and-fresh.*

Cursor pagination is unaffected either way. The cursor is generated from the server page boundary (`attention_repository.dart:142-146`), and relocation happens **within** a page that has already been fetched — whether prompt state arrives joined into that read or alongside it. Neither mechanism moves a row across a page boundary, so no cursor is invalidated.

**Page-bounded relocation does not by itself satisfy §4.6's first-paint guarantee, and rev 5 wrongly treated the two as one question.** The server returns 50 rows in chronological order (`attention_repository.dart:56,118`). If the newest 50 are all fresh pending prompts, the first page contains no chronology to show once two are pinned and the rest collapse; conversely a fresh prompt sitting below 50 news rows is not even a pinning candidate. Cursor integrity is not a display guarantee.

Rev 6 dismissed the breaking distribution — 50 consecutive fresh invite-accepts — as one the product does not produce. **That dismissal is withdrawn: nothing enforces it.** Invitations are created one per action (`friends_screen.dart:108`), but `InvitationCase.create` imposes no per-inviter quantity quota (`invitation_case.dart:62`), there is no bulk-send endpoint, `inviteAccepted` receipts do not collapse (`attention_intent_case.dart:1110`), and single-item creation says nothing about how many acceptances accumulate before a viewer opens the app. An inviter who has been recruiting can plausibly return to a page of nothing but acceptances.

The guarantee is therefore stated conditionally rather than defended by an assumption:

> **If the fetched page contains any chronological row, at least one is visible on first paint.** If it contains none, the branch shows the collapsed prompt row and fetches the next page rather than presenting an empty feed.

The 50-prompt page is an explicit test case with defined behaviour, not an excluded one. Making the guarantee unconditional would require the bounded prompt projection fetched independently of the chronological page; that remains the fix if this state turns out to be common rather than merely possible.

**Implementation constraint.** `InviteAcceptedSetupPort.fetchPrompt(subjectId)` is per-subject (`invite_accepted_setup_case.dart:13`) and the card loads it lazily (`_PromptLoadPhase.loading`). Pinning requires prompt state **before** the feed renders, or rows will reorder after paint.

A static `pending` flag on the receipt payload does **not** suffice, and rev 4's claim that it was an equivalent option is withdrawn. Dispatch stores an event-time projection (`attention_dispatch_repository.dart:84-88,140-141,168`) and the feed read never joins prompt state (`attention_repository.dart:82-104`), while `answer`/`skip` write a different table entirely (`invite_seed_attestation_case.dart:63-95`, `invite_seed_prompt_repository.dart:66-101`). A frozen flag would therefore read `pending` forever. The existing card only refetches when the receipt id or payload changes (`invite_accepted_receipt_card.dart:68-77`), so a batch fetch alone inherits the same staleness.

The requirement this document owns is **observable**, not mechanical: *settling a prompt on one device converges its placement and its available action on every other connected device, without a cold restart, for a receipt that is already mounted and already seen.*

Two things follow, and rev 5's "projection **or** batch + invalidation" phrasing wrongly made the second optional: state must be fresh **at read**, and something must **cause** a read — a join is fresh when fetched but does not fetch. Which mechanism satisfies each, the projection's own authorization predicate, and the acceptance wiring are the implementation plan's (§2.4). Authoritative storage alone does not prove convergence.

## 6. Badges

One indicator per destination, two states, priority-ordered.

**Activity:**
- pending triage items > 0 → **numeric badge**, the count of Inbox `needsMe` rows;
- else unread > 0 → **dot**;
- never both.

The number is bounded by the triage lifecycle (`inbox_set_status`) rather than accumulating indefinitely. It is not monotonically decaying: restore-rejected returns an item to `needsMe` and increments it (`inbox_cubit.dart:293-296`). A prompt never contributes; a `pending` prompt that the user has already seen produces no signal, by design — the pinned position is the reminder. **The badge reports arrival; placement reports openness.**

**My Work:** the numeric badge counts **authorized live obligations** — receipts with `requiresAction` and no settlement, under the same authorization as the scope itself. It is deliberately *not* a count of unseen obligations: `isSeen` and `isLiveObligation` are independent (`attention_receipt.dart:35`), so an already-read unsettled review would vanish from an unseen-based count while still being owed. See the implementation plan §2.5.

Both states carry distinct accessible descriptions ("3 requests need your response" vs. "new activity"). The dot-vs-number distinction is the second channel and is already the M3 `Badge` small/large dichotomy.

**Why rev 2's formula is withdrawn.** It summed pending triage items and `needsYouTotal`. But `needs_you_total` is computed as `COUNT(*) FILTER (WHERE requires_action AND settlement_kind IS NULL)` with **no `seen_at IS NULL` filter**, while `unread_total` beside it does filter on `seen_at` (`server/.../attention_repository.dart:89-95`). Settlement is a manual gesture nothing else performs — triaging an Inbox item does not settle receipts, and reading one does not settle it. The badge would therefore converge on a permanent number equal to the user's lifetime count of unsettled obligations, training users to ignore the one signal this document exists to make meaningful.

Moving obligations to My Work removes that defect from Activity's critical path. It does not fix it; the implementation plan does, by making the live count decay through expiry settlement rather than by filtering on seen.

## 7. Navigation contracts

Each entry path is specified separately. Rev 2's "opening shows the feed, always" collided with existing behaviour.

- **Cold start / deep link.** `/home/updates` → `/home/inbox?tab=receipts` (`root_router.dart:177-182`) and `/notifications` chaining through it keep working and land on the feed. Notification-open intents constructing the Receipts destination (`root_router.dart:553`) keep working. Only `'receipts'` was ever a recognised `tab` value (`inbox_screen.dart:56-57`, `consts.dart:62-63`), so URL breakage is minimal.
- **Branch return.** Restores the last view, scroll offset and search text. Feed views own scroll keys (`updates_feed_pane.dart:177-178`); the keep-alive / page-storage machinery (`inbox_screen.dart:369`) is re-pointed, not deleted.
- **Reselect.** Scrolls the feed to top and clears search. Full stop. Rev 2 proposed a "second reselect opens triage" gesture; withdrawn — `HomeTabReselectCubit` is a pure counter (`home_tab_reselect_cubit.dart:14-28`), a temporal double-gesture has no precedent, no discoverability and no accessibility mapping, and triage is already reachable from an always-visible row.
- **Forward-success intent.** `requestInboxWatching(beaconId)` from the forward snackbar (`forward_messages.dart:145-152`) currently animates to the Watching tab (`inbox_screen.dart:84-94,119-124`). With Watching demoted to a pushed route this intent must be explicitly re-pointed to that route, scrolled to the named Request. **This is a hard requirement, not a detail:** it is the feedback edge of the forwarding loop.
- **Return from triage or Request detail.** Restores feed position.

**Feed view state is per-destination; receipt state is per-account.** `AttentionCase` is a singleton holding a shared `activeView` and `_search` (`attention_case.dart:39,117`), and every `UpdatesFeedCubit` adopts the active view from that shared snapshot (`updates_feed_cubit.dart:29`). Moving the "Needs you" view to My Work by relocating the widget would therefore let one destination overwrite the other's view and search on every visit.

The split is: receipts, acknowledgement and summary stay account-wide and shared; **view selection, search text, page and cursor become per-destination.** Round-tripping Activity → My Work → Activity must restore what Activity had, and that is an acceptance condition rather than an implementation note.

## 8. What My Work must gain

This proposal is two changes, not one. Activity cannot shed obligations unless My Work accepts them.

- The **Needs you** view moves to My Work with its meaning intact, backed by `AttentionView.needsYou`.
- My Work's badge becomes a numeric obligation count. Today `hasMyWorkDot` is the intersection of `myWorkBeaconIds` with unread beacon ids (`home_attention_state.dart:49`) — "something is new in your Requests", with no distinction between a chat message and a help offer.
- The overlap rule ("My Work wins", `home_attention_state.dart:29-30`) is preserved and becomes semantically correct rather than incidental: obligations were always My Work's.

**8.1 My Work's scope gains an obligation set — and this is server work.** Today the scope is authored non-archived Requests plus help offers with `status: {_eq: 0}` (`my_work_fetch.graphql:6-23`, archive exclusions at `:10,22`), and the whole path — `my_work_repository.dart:41-54` → `my_work_case.dart:114-124` → `derive_my_work_cards.dart:199-212` — handles exactly those two sets. The rule it gains:

> **Any Request carrying a live obligation for the viewer is in My Work's scope, regardless of archive state or help-offer status.**

This is deliberately broader than the `reviewOpened` → `formerCommitter` hole that motivated it (§2.2). The same hole exists for an author who archived their own Request and then received a help offer: `authoredNonArchived` excludes it while the obligation is real. Archive is a display preference over the user's own work list; a live obligation with a counterparty outranks it. When the obligation settles, the Request leaves the obligation set and reverts to whatever the other two sets say about it.

**Rev 4 asserted this as a client-side scope edit. That was wrong and is withdrawn.** "Carries a live obligation" is a predicate over authorized rows in `notification_outbox` (`attention_repository.dart:82-104`). That table is **not registered in Hasura metadata at all**, so no amount of condition-adding to My Work's existing GraphQL can express it. Beacon reads additionally require `can_read_content` (`hasura/metadata.json:274-277`), and holding an obligation does not confer read permission.

§8.1 is therefore a **server contract plus four client changes**, enumerated in the implementation plan §2.1 and §3. The one that is architectural rather than mechanical, and so belongs here:

> **Archive changes authored and help-offered membership only. It never removes a Request that is in scope because of a live obligation.**

This is not a detail of the existing archive path — it contradicts it. `my_work_cubit.dart:229` unconditionally removes the Request from state after archiving, and `:232` increments the archived count. The invariant means membership has a *source*, and archiving revokes one source rather than the row.

Rev 4's claim that global and scoped counts "coincide by construction" is withdrawn as a pre-implementation assertion, and rev 5's restatement of it needs one correction: a Request can leave scope through **authorization loss** as well as settlement — content permission is lost on block (`m0162.dart:15`) and content-policy receipts are excluded at read time (`m0117.dart:39`). "Left scope" therefore does not imply "settled", and nothing may treat authorization loss as a terminal settlement.

## 9. Terminology

**Activity** / «Активность» is a new user-facing product noun and must be added to `CONTEXT.md` §Terminology before use, with `scripts/check-user-facing-terminology.sh` updated accordingly. Internal identifiers stay `inbox`. The change also carries the mandatory version bump and `web/index.html` cache-buster sync.

## 10. Withdrawn from earlier revisions

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
11. **Routing a single pending triage item to the Request detail.** Still withdrawn, but on operational-consistency grounds — the "private dismissal path" reason given at the time does not exist (§4.3, §13).
12. **A `staleAt` column for prompt staleness.** Staleness is display-only; the column is disproportionate (§5.4).
13. **Three pinned prompts, and an expanded-by-default resolved section.** Both violate the measured first-screen budget (§4.6).

Withdrawn from revision 4:

14. **§8.1 as a client-side scope edit.** `notification_outbox` is not in Hasura metadata; the predicate is unreachable from My Work's GraphQL (§8.1; implementation plan §2.1).
15. **"Coincidence by construction" as a pre-implementation argument.** It holds only after the live-obligation contract and expiry settlement ship, and must be test-asserted (implementation plan §2.6).
16. **The private-vs-forwarder dismissal justification.** Both dialogs write the same field, and the trigger exposes it to the sender (§4.3, §13).
17. **"A payload `pending` flag is an equivalent option."** A frozen event-time projection reads `pending` forever (§5).
18. **"Watching's seeing job is already fully served by the feed."** True only for admitted watchers and status transitions (§4.7).
19. **"Neither server item is on Activity's critical path."** Several are, and the shipping order is now owned by the implementation plan §1.

Withdrawn from revision 5:

20. **"Only prompt convergence gates the Activity change."** Removing "Needs you" before My Work can accept obligations strands them (implementation plan §1).
21. **"A third input, card derivation and refresh triggers suffice for §8.1."** Archive would still remove the card; membership needs a source (§8.1).
22. **"An unseen-obligation counter is an acceptable badge source."** `isSeen` and `isLiveObligation` are independent (§6).
23. **"Invalidation belongs to the batch branch only."** It is required in both (§5).
24. **"Scope-exit implies settlement."** Authorization loss also exits scope (§8.1).

Withdrawn from revision 6:

25. **"The card itself is unchanged."** Its presentation is; its data path is not (§5).
26. **"50 consecutive fresh invite-accepts is not a state this product produces."** Nothing enforces that — no quota, no bulk endpoint, no collapse (§5.7).
27. **"Step 3 is four client changes."** It is a shipping gate that must also deliver the destination view, its settlement actions and per-destination sessions (implementation plan §1).

## 11. Open questions

Nothing is outstanding that blocks implementation. Rev 7 closed the two that were: pin ordering and `N` (§5.5.1), and the Watching case enumeration (§4.7).

What remains is optional or belongs to a later change:

1. **The 7-day prompt staleness window** (§5.4) is a guess. Display-only and client-side, so it is cheap to change and safe to ship wrong.
2. **Whether `mutual_connection_formed` becomes the second prompt-class member** (§2.3). Out of scope; §5's rules accept it without a fourth mechanic.
3. **Whether NOW-line edits keep emitting `coordinationChanged`** after the cleanup's first step, or gain a dedicated event type (implementation plan §4).

## 12. Review status

| pass | reviewer | verdict |
|---|---|---|
| rev 1 | codex / Astra (GPT-6) | reject as written |
| rev 2 | cursor-agent / Kimi K3 High | REJECT (spine sound) |
| rev 3 | codex / Astra | incomplete — budget exhausted at ~108k tokens; 2 findings recovered from the trace |
| rev 3 | cursor-agent / GLM 5.2 High | ADOPT WITH CHANGES |
| rev 4 | codex / Astra | **REJECT** — 1 blocking, 5 major |
| rev 5 | cursor-agent / Kimi K3, Gemini 3.7, GLM 5.2 | **not performed** — Cursor account budget exhausted |
| rev 5 | cursor-agent / Grok 4.6 Fast | **not performed** — ran without error but emitted no output; retry abandoned (token cost) |
| rev 5 | codex / Astra | **REJECT** — 1 blocking, 7 major, 1 minor |
| rev 6 | codex / Astra | **REJECT** — 4 high, 4 medium; all completeness or cross-document, none contesting the design |
| rev 7 | — | not yet reviewed |

**The rev 5 row is empty for budget reasons, not for lack of findings.** Three reviewers refused on an account-wide monthly cap and a fourth produced nothing; none of them read the document and declined to comment. An empty cell here carries no evidence either way, and rev 5 should not be treated as having survived a peer pass merely because the table has no findings under it.

Across seven passes the **spine has never been contested**: the feed as the branch body, triage as a bounded summary above it, obligations belonging to My Work, Watching as a Request collection, prompts placed rather than counted. Every rejection has been of a supporting mechanic or a justification, and in three cases of a factual claim about the codebase that turned out to be false.

The rev 4 pass was the most damaging so far, because it invalidated reasoning rather than detail:

- **§8.1 was declared, not designed.** `notification_outbox` is absent from Hasura metadata, so the invariant is a server contract (implementation plan §2.1). Rev 4's "coincidence by construction" rested on it and fell with it.
- **§4.3's justification was inverted.** The "private" dismissal note is exposed to the forwarder (§13). The conclusion survived on different grounds; the reasoning did not.
- **The expiry premise was wrong in the document's favour.** Rev 4 speculated review windows might close lazily with no hook. There is a per-minute sweep — but it never revisits already-closed windows, so a backfill is mandatory.
- **§4.7 and §5's payload option** both rested on claims that were true only in part.

Rev 5 corrected four justifications and expanded the server work from two items to six. Rev 6 split the document: that server work, the cleanup ordering and the blast radius are now the implementation plan's, because the rev 5 pass's blocking finding was about **shipping order** — material an architecture document cannot adjudicate. Rev 7 folded the rev 6 findings, none of which contested the design; that pass was entirely about completeness and about which document owns which claim.

No product decision and no layout has changed since rev 3.

## 13. Out of scope: a shipped privacy defect

Found while verifying §4.3. Recorded here because this document must not silently depend on it, and because it should be fixed independently of anything proposed above.

`showInboxDismissDialog` presented the hint **"Optional note (only you see this)"** (l10n `inboxDismissDialogHint`). The note is not private. Both dismissal dialogs call `inboxCubit.reject(..., message: msg)` (`inbox_screen.dart:753-765`), which writes `rejection_message` on `inbox_item` (`inbox_cubit.dart:285-289,336-339` → `inbox_set_status.graphql:8`). The trigger `inbox_item_on_rejection_update` copies it to `beacon_forward_edge.recipient_rejection_message` for every matching edge (`m0015.dart:67-76`), and Hasura's `user` role may select that column where `sender_id` matches the viewer (`hasura/metadata.json:1399-1407`).

So a note written under a promise of privacy is readable by the person who forwarded the Request.

**Status: copy corrected as a stopgap; behaviour tracked in [#137](https://github.com/Intersubjective/tentura/issues/137).** `inboxDismissDialogHint` now reads "Optional note — the sender will see it" / «Комментарий необязателен — его увидит отправитель» (`ba3a45905`), so the interface no longer promises what it does not deliver.

**The product decision is that the note must be private.** It therefore needs its own column and permission rather than a share of `rejection_message`, with the dismissal trigger never reading it — see #137, which also records that existing rows cannot be retroactively attributed to one dialog or the other, since both set `status = 2` and write the same column.

One consequence worth carrying forward: once #137 lands, the two dialogs differ in **substance**, not only wording — "remove from my inbox" becomes private and "can't help" stays communicated. §4.3 was rewritten in rev 5 to rest on operational consistency rather than on that distinction, and it stays that way; the distinction returning is a reason the rule is comfortable, not a reason to revisit it.
