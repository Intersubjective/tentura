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
   | Direct addressee (participant role 6) | write, unless they withdrew or were declined (then read) |
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
quotes, deep links, reactions, replies and mention candidates.

## Notifications and realtime

- The author gets an attention item for every question (undirected or not);
  @mentions are drawn from the Questions audience; reply notices reach only
  the audience. Their deep link opens the Questions screen
  (`/beacon/lobby/<id>`).
- Realtime: a separate trigger (`notify_questions_message_change`) sends the
  usual bare `room_message` hint to audience members who are not General room
  recipients; General recipients already get the General hint. No Questions
  text is painted over the socket; clients refetch through the gated API.
  The General notify path (`notify_entity_change`) is unchanged.
- Questions do not move `beacon.last_activity_at`.

## Client

- Request Overview: a **Questions** row, shown only when `BeaconLobbyAccess`
  says the viewer may read; it shows the number of messages they can see.
- Questions screen: newest page first with "Show earlier messages" (pages
  back with `beforeIso`), pull-to-refresh, a composer for write access and a
  one-line read-only note otherwise, `TenturaEmptyState` when empty, the
  author's remove (with `TenturaConfirmDialog`) and "Let back in" fold with
  names from the server. Opening marks Questions seen (settles its attention
  items). A message hint refetches only the newest page; an offer / forward /
  participant / Request hint or a realtime catch-up re-opens.

## Known limits

- General room recipients (including people removed from Questions) still
  receive a bare `room_message` hint (beacon id + message id, no text) for
  Questions messages: the General notify path belongs to the realtime owner.
- No unread badge for Questions beyond the author's attention items.
- Reactions and attachments work through the API with write access but the
  Questions screen does not show them yet.
