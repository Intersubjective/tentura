# Request Questions («Вопросы»)

User-facing name: **Questions** / «Вопросы». Internal name: the Request
**lobby** (`BeaconLobby*` GraphQL, `beacon_lobby` client feature,
`coordination_item` kind 7, `beacon_lobby_ban`). Decision D1 of
`docs/plans/2026-10-22-opus-sprint-decisions.md` (#526, U088 / PRs #543–#544).

## What it is

One conversation per **Request** (never a Post) where the people the Request
was sent to can ask the author before they offer help ("which Saturday?",
"how many boxes?"). **Offer help** stays the commitment step. The whole thread
is public to the Request's addressed audience (owner answer Q2): everyone in
the audience sees every question and every answer.

Questions is separate from the Request's **discussion** (General): General
stays private to admitted participants, and nothing from General is shown in
Questions (no fact quotes) or the other way round (no facts, plan steps,
batons, next moves, promotions or "done" markers on a Questions message).

## Who may read and write — one server-owned policy

The policy is the SQL function `public.questions_access_levels(beacon_id,
user_ids[])` (migration m0254; `questions_audience(beacon_id)` lists everyone
with access). It returns 0 = none, 1 = read-only, 2 = read and write. The
server calls it for **every** operation (open, the entry-row probe, read,
history, seen, post, edit, delete, react, attachment download, mentions,
notifications and realtime delivery) with one set query; the client never
re-implements it and only shows what the server returns.

A person has access when **all** of these hold:

1. The Request content is readable to them (`beacon_can_read_content`: no
   block with the author either way, not deleted, not someone else's draft).
2. They have **current standing** on this Request:

   | Standing | Access |
   |---|---|
   | Author | write |
   | Steward (`beacon_steward` or participant role 1) | write |
   | Admitted participant (`room_access = 3`) | write |
   | Live help offer | write |
   | Live forward edge to them (not cancelled, not answered "Can't help") | write, unless they withdrew or were declined (then read) |
   | Direct addressee (participant role 6) | write, unless they withdrew, were declined or answered "Can't help" (then read) |
   | Live forward edge they answered **"Can't help"** | read-only (Q4) |
   | Withdrawn or declined help offer, no other standing | read-only (Q4); offering again restores writing |
   | Cancelled forward, historical inbox item only | **none** |
   | Discovery-only reader (could read a discoverable Request, nobody sent it) | **none** (Q3) |
   | Hierarchy / context readers (parent or child Requests) | **none** |

3. The author has not **removed** them from Questions (`beacon_lobby_ban`;
   the author can never be removed). A removal outlives withdrawing and
   offering again; only the author lets them back in. Their earlier messages
   stay visible to everyone else.

Writing additionally needs a Request whose lifecycle allows discussion
writes: a closed, cancelled or deleted Request is read-only for everyone who
could read it.

**Blocks between recipients:** a message is hidden from a viewer when its
author and the viewer blocked each other (either way): in the list, reply
quotes (including the replied-to id), deep links, reactions, replies,
mention candidates and realtime hints.

## Notifications and realtime

- The author gets an attention item for every question (undirected or not);
  @mentions are drawn from the Questions audience; reply notices reach only
  the audience. Their deep link opens the Questions screen
  (`/beacon/lobby/<id>`). Questions notifications never store or push the
  message text ("New message in Questions"), because a receipt outlives a
  later ban or block; the text is read only through the gated API.
- Realtime: hints about a Questions message, its reactions and its
  attachments go **only** to the Questions audience
  (`questions_hint_recipients`, m0255: `questions_audience` minus anyone
  blocked with the message author), through the Questions publishers
  (`notify_questions_message_change`, `notify_questions_reaction_change`,
  `notify_questions_attachment_change`). They use the General wire kinds and
  envelopes (bare `room_message` with the message id; `room_reaction` with the
  Request id only). The General publishers (`notify_entity_change`,
  `notify_room_message_attachment_change`) skip Questions rows through a
  trigger `WHEN` clause, so General room recipients outside the audience
  (removed from Questions, blocked with the author) get nothing; General rows
  are published exactly as before. Moving a row into or out of Questions
  (never done by the API) publishes to the audience only; deleting the
  Questions item deletes its messages first so their hints stay scoped; a
  Questions message can never link a poll (`room_poll` goes to General). No
  Questions text is painted over the socket; clients refetch through the
  gated API.
- The Questions item itself (`coordination_item` kind 7, created on first
  open) publishes **no** `coordination_item` hint (m0257): the General
  coordination-item triggers skip kind 7 (before or after an UPDATE), so
  nobody, inside or outside the audience, learns from the socket that
  Questions was opened. No client reads the item through that hint.
- Questions do not move `beacon.last_activity_at`.

## Client

- The way in, shown only when `BeaconLobbyAccess` says the viewer may read
  (with the number of messages they can see):
  - people not inside the Request yet (the showcase page: recipients before
    offering help, "Can't help", withdrawn) get a **Questions card** under
    the description and facts, at every width (#526 — asking before offering
    is the point);
  - insiders (author, admitted helpers) get the **Questions row** on Overview.
  Discovery-only readers never see either (the probe says no). The probe is
  re-read on message / offer / forward / participant / Request / inbox
  hints, whenever the Request page's own view of the viewer's standing
  changes (created, offered, admitted, "Can't help", status), and up to three
  times with backoff after a failed read (#655).
- Copy follows the reader (#657): the author is told who can ask them and
  answers ("Write an answer"); everyone else is asked to "Ask the author".
  The author's messages carry an **Author** mark (`BeaconLobby.authorId`).
  A read-only reader is told their own reason from
  `readOnlyReason` (`closed`, `cant_help`, `withdrew`, `declined`); someone
  the author removed is told so (`removed`, from the probe). The reason is
  computed on the server from the caller's own standing only
  (`QuestionsStandingFacts`), never someone else's.
- Notifications (#656): a Questions message receipt (`room_message_posted`
  with a `coordinationItemId`) reads "New message in Questions" on cards,
  the Timeline and Updates (never "thread"), and tapping it on a My Work card
  opens Questions; the push deep link already did.
- Desktop (#658): Enter sends (the Chat composer's `TextInputAction.send`),
  and the screen sits in the same content column as its top bar.
- Questions screen: newest page first with "Show earlier messages" (pages
  back with `beforeIso`), pull-to-refresh, a composer for write access and a
  one-line read-only note otherwise, `TenturaEmptyState` when empty, the
  author's remove (with `TenturaConfirmDialog`) and "Let back in" fold with
  names from the server. Opening marks Questions seen (settles its attention
  items). A message hint refetches only the newest page; an offer / forward /
  participant / Request hint or a realtime catch-up re-opens.

## Known limits

- The Timeline sheet names the sender but never the question's text
  (notices carry none, by design).
- No attachments in Questions: room images are served from the shared image
  store, which the Questions policy does not gate. Reactions work through the
  API with write access but the screen does not show them yet.
- Removing someone from Questions has no realtime hint to that person; their
  next refetch or open shows "not for you".
- Opening Questions has no realtime signal of its own (m0257); other devices
  and audience members see it with the first Questions message hint or their
  next refetch.
