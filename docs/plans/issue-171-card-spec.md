# Issue #171 — For You card: implementation spec

Status: **decisions closed by the owner 2026-09-19.** Rev 1.
Rationale, evidence and alternatives considered live in
[`issue-171-activity-label-comprehension-analysis.md`](issue-171-activity-label-comprehension-analysis.md);
this document is *what to build*.

Depends on [`request-centric-attention-plan.md`](request-centric-attention-plan.md) rev 1 (R1–R10, E1–E32,
U01–U11) and **amends it in three places** (§3).

## 0. How to consume this

For the agent folding this into an implementation plan:

- **§3** must be written into the plan text — it changes two decisions and one test assertion.
- **§4** is a **blocking server prerequisite inside U02**. The client spec is not implementable without it.
- **§5–§10** are the client spec, landing in U05 (grouped stream) and U06 (event block + dismiss), with the
  cross-surface consolidation in U09/U11.
- **§11–§13** are acceptance.
- Everything in §1 is decided. Do not re-open, re-derive or silently resolve differently.

---

## 1. Decisions (closed)

| id | Decision |
|---|---|
| **D-171-1** | **V-B**: rename the Watching word family to «Следить / Слежу» / "Follow / Following". Must land **before U09**, because E29 turns the word into permanent navigation furniture. |
| **D-171-2** | **Tombstones stay and gain the private ×.** Owner's formulation: *"их задача — просто показать юзеру, что «что-то тут было, это последствия действия, которое ты или кто-то другой совершил, воспоминание, от которого можно избавиться»"*. See §3 A1. |
| **D-171-3** | Add `selfAuthored`, `headlineTreatment`, `coalescible` to the event contract (schemaVersion 3) under the failing guard test. |
| **D-171-4** | Build the **full unified card** (§6), not a minimal note-preview restoration. |
| **D-171-5a** | Inside a card's collapsed event list, the **first slot is pinned to the latest forward carrying a note**; the rest sort by time. |
| **D-171-5b** | **«ещё N» always opens the Request's Timeline.** Never expands in place, on any window class. |

---

## 2. What the card is for (do not re-derive)

On For You a card serves exactly one decision: **take it / pass it on / later / no.** Everything on the card is
evidence for that decision, ranked by weight:

1. what a specific person said to me personally (the forward note) — the premise of the product, maximum weight;
2. what is being asked — the title;
3. why me — the forwarder's capability chips;
4. how urgent — deadline, only while near;
5. who authored it, who is already involved.

Category, "updated N ago", room hints and non-terminal status lines carry ~zero weight and live on the detail
screen. The governing principle is **rank, don't delete**: the previous card failed by being unranked, the current
one by being emptied.

---

## 3. Amendments to `request-centric-attention-plan.md` rev 1

**A1 — E2 gains the private ×.** E2 currently reads that terminal outcome rows have *"no dismiss affordance"*.
Replace with: tombstones **are removable by the private × (E7 semantics, `seen_at` as dismissed)**. Everything else
in E2 stands — they remain not attention objects, never bump, carry no dot, no sub-cards, and are excluded from
grouping (E4).

Rationale: the tombstone's job is to say *"something was here; it is the consequence of an action you or someone
else took"* — a **memory**, and a memory the user may discard. Without the ×, For You accumulates a permanent
sediment, R10 ("a surface the user can bring to zero") is unkeepable and E31's reward state can never fire.
This does not re-introduce E17's "two make-this-go-away gestures on one card" problem: E17 governs **pinned,
unanswered** forwards, which keep their outcome buttons and no ×. A tombstone is already answered — nobody is
waiting on it — so the private × is the correct and only gesture.

**A2 — plan §8 test 4 is rewritten.** From *"Tombstone rows never bump, never group, never show a ×"* to:
*"Tombstone rows never bump, never group, carry no dot and no sub-cards, and are removed by the private × only
(never by a CTA, never silently)."*

**A3 — tombstone copy becomes a past-tense event sentence**, which follows from A1's rationale: a memory of an act
is an event, not a state. See §8. This is the direct fix for #171's «Вы наблюдаете».

**A4 — E30's Timeline entry becomes load-bearing.** With D-171-5b, «ещё N» has no other destination. The Timeline
entry point must exist on every card before the card ships, not as a later polish item.

---

## 4. Data contract — blocking prerequisite in U02

**The problem.** Forward notes and the relay chain come from `InboxProvenance`, parsed from the Hasura computed
field `inbox_item.inbox_provenance_data` — i.e. from the **Inbox** query. `AttentionReceipt` carries only
`id / category / kind / priority / title / body / actionUrl / createdAt / collapsedCount /
presentationPayloadJson / surface` and friends. It has **no provenance at all**.

U02 replaces For You with one grouped read model over `visible_attention_receipts`. A grouped `beacon:` row
therefore **cannot render a note** unless U02 carries provenance through. This is server work, not widget work,
and it gates everything below.

**Required on each grouped `beacon:<id>` row:**

| field | type | used by |
|---|---|---|
| `senders[]` → `{ id, displayName, imageId, notePreview, reasonSlugs[], mr }` | list | forward mini-cards (§7.1), coalescing (§7.3) |
| `totalDistinctSenders` | int | «ещё N переслали» overflow (§7.3) |
| `strongestNotePreview` | string | first-slot note when `senders[]` is truncated (D-171-5a) |
| `beacon.title`, `beacon.author`, `beacon.imageId`, `beacon.endAt` | — | header (§6.1) |
| `allowsForward` | bool | action row (§6.3) |

`strongestNotePreview` already exists and is already MR-ranked server-side, so "the note is visible without
expanding" needs no new ranking logic — only plumbing.

**Shape note.** Reuse the existing `inbox_provenance_data` JSON shape verbatim and expose it on the grouped row;
`InboxProvenance.parse` and `withoutViewer` then work unchanged on the client. Do not invent a second provenance
DTO.

---

## 5. Component map

### Create

| Component | Where | Notes |
|---|---|---|
| `RequestAttentionCard` | `features/inbox/ui/widget/request_attention_card.dart` | the unified card (§6); one widget, variants by state (§9) |
| `AttentionMiniCard` | `features/inbox/ui/widget/attention_mini_card.dart` | promote the private `_EventSubcard` out of `activity_event_subcard_block.dart` into a public widget and add the `forward` kind (§7) |
| `TombstoneRow` | `features/inbox/ui/widget/tombstone_row.dart` | §8; replaces `ActivityForwardRow` |
| `TenturaRelationChip` | `design_system/components/tentura_relation_chip.dart` | there is no generic chip primitive today (`ForwardCapabilityChips` uses `RawChip` directly). Raw visual constants in feature UI are lint-forbidden, so the chip belongs in the design system. Build it through the `material-3-flutter` skill. |

### Reuse unchanged

`BeaconIdentityTile` (cover), `TenturaAvatar.medium/.tiny`, `ForwardCapabilityChips`, `CompactForwarderAvatars`,
`TenturaTextAction`, `TenturaSectionHeader`, `TenturaHairlineDivider`, `TenturaStatusText`, `TenturaPresenceDot`
(unread dot, `tt.unreadDotSize`), `TenturaCountBadge`, `BeaconOverflowMenu`, `inbox_card_actions.dart`
(`inboxOfferHelp`, `inboxForwardItem`), `rejection_dialog.dart`, `ActivityEventSubcardBlock`'s paging machinery
(`visibleCap`, «ещё N», lazy load).

### Retire

| Widget | When | Replaced by |
|---|---|---|
| `ActivityOfferCard` + `ActivityOfferBoundedShell` | U05 | `RequestAttentionCard` (pinned variant) |
| `ActivityForwardRow` | U05 | `TombstoneRow` |
| `inbox_forward_attribution_copy.dart` | U05 | header sub-line `· от X` (§6.1) |
| `InboxItemTile` + `InboxCardForwardsFold` | **U09/U11**; done in U17b | `InboxWatchlistRow` (`features/inbox/ui/widget/inbox_watchlist_row.dart`) on Watching / Rejected — **not** `RequestAttentionCard`, as this row originally said. Watching and Rejected are collections of stances, not attention surfaces: the attention card's dot, count and event sub-cards have nothing to show there. `_SenderNoteBlock`'s content was ported into the For You forward mini-card in U16a as required, and the fold itself turned out to be dead — both live callers passed `showProvenance: false`. What survived into the new row is the calendar deadline line. |

---

## 6. Card anatomy

All spacing, colour and type through `context.tt` and `TenturaText.*`. No raw constants in feature UI (lint).

```
┌──────────────────────────────────────────────┐   BeaconCardShell-equivalent container:
│ ▢  «Наши требования»                     ⋮   │   tt.cardRadius, tt.cardPadding, tt.surface,
│    Bai Yue · до 20 сент.                 ●   │   1px tt.borderSubtle
├──────────────────────────────────────────────┤
│ (ава) Bai Yue переслал                2 ч ✕  │   §7 mini-cards
│   ▏ Ты же с этим возился, глянь              │
│   ▏ [ремонт] [авто]                          │
│                                              │
│ (ава) Глеб предложил помощь          40 м ✕  │
│   ▏ Могу дать прицеп на выходных             │
│                                              │
│ ещё 3 · Хронология                           │   §6.2 footer meta
├──────────────────────────────────────────────┤
│ [Предложить помощь]   Переслать   Следить    │   §6.3 action row
└──────────────────────────────────────────────┘
```

### 6.1 Header — identity only (K1)

| Slot | Spec |
|---|---|
| leading | `BeaconIdentityTile(beacon:, size: tt.avatarSize)`, then `SizedBox(width: tt.avatarTextGap)` |
| title | `TenturaText.titleSmall(tt.text)`, `maxLines: 2`, ellipsis. Rendered per `headlineTreatment`: `beacon` ⇒ «…» (ru) / “…” (en); `user` ⇒ bare name; `system` ⇒ bare label |
| sub-line | `TenturaText.bodySmall(tt.textMuted)`: `<author>` + ` · ` + deadline. Deadline is rendered **only when near or overdue**; overdue uses `TenturaStatusText` with `tt.danger` |
| relation chip | `TenturaRelationChip` on the title row's trailing side when the viewer has a relation — «Помогаю» / «Слежу». Not rendered on the pinned variant (no relation yet) |
| unread dot | `TenturaPresenceDot`-style, `tt.unreadDotSize`, trailing; present iff ≥1 undismissed optional event (E19) |
| overflow | `BeaconOverflowMenu` — «Не могу помочь», «Граф пересылок», «Хронология», «Пожаловаться». This also restores the forwards-graph entry point, which the current `ActivityOfferCard` dropped entirely |

**Header carries nothing else.** Category, `updated_at`, room hints and non-terminal status lines are removed
(§2). Gap between header and the mini-card list: `tt.rowGap`.

### 6.2 Footer meta

One row, `TenturaText.bodySmall(tt.textFaint)`, `tt.tightGap` above:

- `ещё N` → `TenturaTextAction`, **opens the Timeline** (D-171-5b), never expands;
- `Хронология` → `TenturaTextAction`, Timeline (E30). When «ещё N» is absent this is the only Timeline entry and
  is always rendered;
- `Очистить всё` → `TenturaTextAction`, right-aligned, watermark-based clear (E25), batched (E27), undo (E10).
  Rendered only when ≥1 undismissed optional event exists.

### 6.3 Action row

`Wrap` with `spacing: tt.rowGap`, `runSpacing: tt.tightGap`, separated from the body by `TenturaHairlineDivider`.

- **Pinned (unanswered forward):** `FilledButton.tonal` «Предложить помощь» (`minimumSize: Size(0, tt.buttonHeight)`),
  then `TenturaTextAction` «Переслать» (iff `allowsForward`) and «Следить». **No ✕ on the card** (E17).
  «Не могу помочь» lives in ⋮ and opens `rejection_dialog` — it is a *social* act and must be a named action, never
  the quiet × (E17). This replaces today's ✕-opens-rejection-dialog, which dresses a social act as a private gesture.
- **Grouped (already answered):** no action row; the footer meta row carries `Очистить всё`.

---

## 7. Mini-cards

One shape for everything under the header (K2). Kinds differ by leading glyph/avatar and by body, never by layout.

```
(avatar|glyph)  <event line>                        <age>  ✕
   ▏ <quoted body — note / message excerpt>
   ▏ [chips]
```

- leading: `TenturaAvatar.medium` when an actor profile exists, else `updatesFeedGlyphFor` icon at `tt.iconSize`;
  `SizedBox(width: tt.avatarTextGap)`
- event line: `TenturaText.bodySmall(tt.textMuted)`
- quoted body: `TenturaText.bodySmall(tt.textMuted)` behind a 2px rule in `tt.border`, indented by
  `tt.avatarSize + tt.avatarTextGap`. **Left-aligned** (K4) — the old right-aligned italic note borrowed chat
  grammar backwards and is not reproduced
- age: `TenturaText.withTabular(TenturaText.bodySmall(tt.textFaint))`, `Tooltip` with the absolute timestamp
- ×: ≥48 dp target, `tt.iconSize` glyph in `tt.textFaint`; E32 mechanics — hold layout height until pointer-up,
  animate through a placeholder, announce removal

### 7.1 Forward mini-card

Event line: «<Имя> переслал». Body: `notePreview`. Chips: `ForwardCapabilityChips(slugs: sender.reasonSlugs)`
under the note, `tt.tightGap` below it. The chips belong **here**, attached to a forwarder — never in the header,
because they describe why *that person* chose *you*.

### 7.2 Other kinds

Message, help offer, status change, participant change, review — all existing `presentationKey`s, rendered by
`resolveUpdatesFeedRowCopy`. Where the server headline is just the actor name, prefer `body` so the personal note
shows (already the behaviour in `activity_event_subcard_block.dart`).

### 7.3 Ordering, collapsing and coalescing

- visible count: 1 on `WindowClass.compact`, 3 otherwise (existing `visibleCap`) — collapse by **count, not by
  type** (K5);
- **first slot is pinned to the latest forward carrying a note** (D-171-5a); the remaining slots sort by time,
  newest first (K7). Genealogical chain order lives in the Timeline and the forwards graph, not on the card;
- same-kind coalescing (E11): «3 новых сообщения» = one line, one ×;
- **notes are never coalesced** (K6, `coalescible: false`). Note-less forwards coalesce into one line —
  «ещё N переслали» + `CompactForwarderAvatars` — but every forward *with* a note keeps its own mini-card.
  Rationale is E28: the note exists nowhere else on the card, so coalescing destroys information.

---

## 8. Tombstone row (D-171-2, A1, A3)

A tombstone is **not** a card. It is a single compact row, outside grouping, that says *"something was here"*.

```
[avatar]  «Наши требования» · от Bai Yue            5 мин   ✕
          Вы предложили помощь
```

- header line: quoted title + `· от <forwarder>`, `TenturaText.titleSmall(tt.text)`, weight w500;
- second line: a **past-tense event sentence** (A3), `TenturaText.bodySmall(tt.textMuted)`;
- leading: the last forwarder's **avatar**, not the paper-plane glyph — the current glyph is a *send* affordance
  and misreads as "I sent this";
- trailing: the private ✕ (E7 semantics). For `notInterested`, also `Вернуть` as a `TenturaTextAction`;
- no chip, no dot, no sub-cards, never bumps, excluded from grouping (E2 as amended).

Copy:

| outcome | now RU | spec RU | spec EN |
|---|---|---|---|
| `helping` | Вы помогаете | **Вы предложили помощь** | You offered help |
| `watching` | Вы наблюдаете | **Вы начали следить** | You started following |
| `notInterested` | Не интересно | **Вы отказались** | You declined |
| `closedBeforeResponse` | Закрыт до вашего ответа | **Автор закрыл запрос до вашего ответа** | The author closed it before you answered |
| `deletedBeforeResponse` | Больше недоступен | **Запрос удалён** | The request was deleted |

Every line now has a subject, a verb and a tense — which is what makes it readable as a memory rather than as a
mysterious status. This is the literal fix for #171's reported strings.

---

## 9. State matrix

| State | Header | Body | Footer | Actions |
|---|---|---|---|---|
| Pinned, unanswered forward | cover, title, author, deadline?, ⋮ | ≥1 forward mini-card (guaranteed) | Хронология | Предложить помощь / Переслать / Следить |
| Grouped, viewer helps | + chip «Помогаю» | coalesced events | ещё N · Хронология · Очистить всё | — |
| Grouped, viewer follows | + chip «Слежу» | coalesced events | same | — |
| On «Слежу» screen | + chip «Слежу» | last events | Хронология | Не следить (⋮) |
| On «Отклонённые» screen | + rejection message line | — | Хронология | Вернуть |
| Tombstone | §8 row, not a card | — | — | ✕ (+ Вернуть for `notInterested`) |
| No note on any forward | unchanged | mini-card with event line only, no quoted body | unchanged | unchanged |
| One forwarder vs N | `· от X` vs `· от X, +N` | N note-less ⇒ one coalesced line; N with notes ⇒ N mini-cards | unchanged | unchanged |
| No cover image | `BeaconIdentityTile` placeholder | unchanged | unchanged | unchanged |
| Title 1 word / 200 chars | 2 lines max, ellipsis inside the quotes | unchanged | unchanged | unchanged |
| Terminal (closed/deleted) | status line via `TenturaStatusText` | unchanged | unchanged | none |
| Compact vs wide | — | `visibleCap` 1 vs 3 | — | Wrap reflows |

**Height ceiling.** Header + at most `visibleCap` mini-cards + footer + action row. Because «ещё N» never expands
in place (D-171-5b), the card has a hard maximum height by construction. Assert it in a golden.

---

## 10. Copy — V-B rename (D-171-1)

Values only; l10n **keys stay unchanged**. One commit, before U09 and before the next testing session, with a
sweep of sibling #142 issues that quote the old word.

| key | RU now | RU new | EN now | EN new |
|---|---|---|---|---|
| `beaconHeaderWatch` | Наблюдать | **Следить** | Watch | **Follow** |
| `beaconHeaderStopWatching` | Не наблюдать | **Не следить** | Stop watching | **Unfollow** |
| `inboxWatching`, `inboxTabWatching` | Наблюдаю | **Слежу** | Watching | **Following** |
| `inboxWatchingEmptyCalm` | Нечего отслеживать. | **Пока не за чем следить.** | Nothing to watch. | **Nothing to follow yet.** |
| `inboxTabWatchingEmpty` | Нет запросов в наблюдении | **Вы ни за чем не следите** | No requests on your watch list | **You are not following anything** |
| `actionWatch` | Переместить в «Наблюдение» | **Следить за запросом** | Move to Watching | **Follow this request** |
| `actionStopWatching` | Вернуть в «Нужно мне» | **Вернуть в «Ждёт меня»** | Return to Needs me | Return to Needs me |
| `beaconHudYouWatching` | Наблюдаете | **Слежу** | Watching | **Following** |
| `beaconPeopleRoleWatcher` | Наблюдатель | **Следит за запросом** | Watcher | **Follower** |
| `forwardWatching`, `forwardReactionWatching` | Наблюдение / Наблюдает | **Слежу / Следит** | Watching | **Following** |
| `activityWatchingDigest` | …за которыми вы наблюдаете | …**за которыми вы следите** | …you watch | …**you follow** |
| `activityForwardOutcome*` | — | §8 table | — | §8 table |

`actionStopWatching` also fixes side finding 2: it named «Нужно мне» while the destination tab is `inboxNeedsMe`
= «Ждёт меня».

**Register rule (P7), applies to all new copy:** labels about *me* are first-person or bare participle chips
(«Помогаю», «Слежу» / "Helping", "Following"); system sentences addressed to me stay second-person
(«Вы предложили помощь»). Never «Вы помогаете» as a chip.

**Confirmations.** Every action that removes a card from For You raises a SnackBar naming the object **and the
destination**, with undo:

| Action | Confirmation | Actions |
|---|---|---|
| Предложить помощь | «Вы предложили помощь по «X» — запрос теперь в «Моих делах»» | Открыть · Отменить |
| Следить | «Следите за «X» — обновления придут в «Слежу»» | Открыть · Отменить |
| Переслать | existing #110 copy | Открыть · Отменить |
| Не могу помочь | «Убрали «X» из «Для вас»» | Вернуть |

---

## 11. Accessibility

- Card `Semantics` label = the whole sentence: "Запрос «Наши требования», от Bai Yue, 2 новых события, вы помогаете".
  The relation chip must never be the sole carrier of state — today `activity_forward_row.dart:87` labels the row
  with the headline only.
- Mini-card `Semantics`: actor + event + age; `button: true` where tappable.
- × is a labelled button ("Убрать событие"), ≥48 dp, and removal is announced (E32).
- Mark seen/unseen and × reachable by secondary tap and a hover toolbar on pointer devices — **never long-press
  alone** (standing cross-platform rule).
- Contrast and hit targets verified at 360×640 and 1.3× text; the first card must be fully visible on first paint
  (plan §5.5).

---

## 12. Tests and goldens

New / changed assertions:

1. A forward's `notePreview` renders on the **primary** For You surface (A7) — the regression guard.
2. Capability chips render inside the forward mini-card, never in the header.
3. Coalescing: N note-less forwards ⇒ one row; N forwards with notes ⇒ N mini-cards (`coalescible: false`).
4. First collapsed slot is the latest note-bearing forward even when a newer note-less event exists (D-171-5a).
5. «ещё N» navigates to the Timeline and does not change card height (D-171-5b).
6. Card height ceiling holds at `visibleCap` + 1.3× text at 360 dp.
7. Tombstone: has ×, is removed by it, never bumps, never groups, carries no dot and no sub-cards (A2).
8. **For You can be brought to a state with no rows** (A6) — including tombstones.
9. Contract guard fails when an event type omits `selfAuthored` / `headlineTreatment` / `coalescible`.
10. Headline treatment by `objectKeyKind`: `beacon` quoted + attributed, `user` bare + avatar, `system` bare.
11. Pinned card has no ×; «Не могу помочь» exists in ⋮ and opens the rejection dialog.

Goldens retired with their widgets: `ActivityOfferCard`, `ActivityForwardRow`, `ActivityOfferBoundedShell`, and —
at U09/U11 — `InboxItemTile`.

---

## 13. Out of scope

- No change to what Following *does* — only what it promises and where it says the request went.
- No `attention_occurrence` store; grouping stays read-time (plan §9).
- No rework of My Work sections, filters or badge arithmetic beyond the shared mini-card component.
- Notification History stays the global chronological log, and keeps event-headline grammar; **only For You uses
  object headlines**. Write this two-grammar rule into `event-cards-product-design.md` (U01), or it will be
  "fixed" back.

---

## 14. Known risk, to validate on real data

A card with 3 mini-cards is substantial at 360 dp; ten Requests in For You make a heavy list. The guards are the
§9 height ceiling and `visibleCap = 1` on compact. Validate against a seeded account with realistic volume before
U11, not against a mockup.
