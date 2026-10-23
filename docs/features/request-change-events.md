# Who did what on a Request — change events

**User-facing:** a member coming back to a Request sees in its discussion what changed and who changed it;
the author is told, on their Requests card, when somebody leaves or cannot help.

Issues: #528 (lines for edits), #516 (a withdrawal tells the author; the next step is flagged), #486 (the author
hears "Can't help"). Terminology: Request = `beacon`, discussion = `beacon_room`, My desk = `my_work`.

## One mechanism, three channels

Every "who did what" change on a Request is written by its producer, **in the producer's own transaction**,
to at most three channels. Each event declares which channels it uses; nothing else writes them.

| Channel | Who sees it | Written by |
|---|---|---|
| **Room line** — a General system row (`system_message_kind` or `semantic_marker`) | every member of the discussion | the data-layer writer for that event |
| **Activity event** — `beacon_activity_event`, `source_message_id` → the line | the Request's log (room visibility) | the same writer, same transaction |
| **Attention receipt** — `AttentionDispatchIntent` → `notification_outbox` | only the people who must act | the use case, `transaction.record(...)` |

| Event | Room line | Activity event | Attention | Producer |
|---|---|---|---|---|
| Status change | kind 7 `statusChanged` | 16 `beaconLifecycleChanged` | `requestStatusChanged` | `recordBeaconStatusTransition` |
| Next step edited | kind 8 `requestEdited`, `field: nextStep` (coalesced) | 26 `requestEdited` | `coordinationChanged` (existing, noisy) | `BeaconRoomCase.updateRoomNowLine` → `RequestChangeLogPort` |
| Title edited | kind 8 `requestEdited`, `field: title` (coalesced) | 26 `requestEdited` | — | `BeaconCase.update` → `RequestChangeLogPort` |
| Admitted helper withdrew | marker 18 `participantLeft` | 25 `participantLeft` | `helpWithdrawn` → author, stewards | `HelpOfferCase.withdraw` |
| Pending offer withdrawn | — (never in the room) | — | `helpWithdrawn` → author, stewards | `HelpOfferCase.withdraw` |
| Recipient: "Can't help" | — (private) | — | `forwardDeclined` → author only | `ForwardCase.cantHelp` (`beaconCantHelp`) |

## Rules

- **No public performance.** A decline is an answer to whoever forwarded the Request, not a statement to the
  room: it never makes a room line or a log entry. Its note reaches the author's receipt (and, as before, the
  forward edge's sender) and nobody else.
- **Edits coalesce.** One person's run of edits of one field is one line: while their line is still the newest
  General message and younger than 10 minutes (`kRequestEditLineCoalesceWindow`), the next edit updates it
  (`to`, `edits`, and moves it to now) instead of adding a line. The log keeps every edit.
- **Optional updates, not obligations.** `helpWithdrawn` and `forwardDeclined` are optional updates on the
  author's Requests card (dot, ×, cleared on open). A withdrawal also supersedes the author's
  `helpOfferSubmitted` obligation — the update is what keeps that number from "falling on its own"
  (request-attention §5).
- **The next step is checked against the person who left.** `nextStepMentionsPerson` (`tentura_root`) is the
  one rule: whole display name, its first word (two letters or more) or @handle, as a whole word, any case.
  The server stamps `nextStepMentionsActor` on the author's update at withdrawal time; the Request header
  flags the next step live ("Omar left after this was set") until someone edits it.
- **"New since you were here"** is the existing unread band in the discussion: edit, status and leave lines are
  ordinary rows after the viewer's read watermark, so the band lands on the first one the viewer has not seen.
  (They count for the band, not for the unread badge — system lines never bump activity or unread counts.)

## Payloads

- `requestEdited` line: `{version: 1, field: "nextStep"|"title", from, to, edits?}`, author = actor.
- `requestEdited` activity event: `diff {field, from, to}`.
- `helpWithdrawn` receipt payload: `withdrawReason` (a known key, gated like the excerpt), `leftDiscussion`, `nextStepMentionsActor`, `excerpt` (note);
  destination `beacon_people_offer` → the person.
- One formatter reads `helpWithdrawn` for every surface (Request card change line, Request-scoped rows,
  Updates): `whoDidWhatReceiptDisplayCopy` (client). A `promiseWithdrawn` receipt that carries a
  `withdrawReason` was written before 7.46.0 gave withdrawals their own event and reads the same way; a
  coordination promise's `promiseWithdrawn` never carries one.
- `forwardDeclined` receipt payload: `excerpt` (note), `targetEntityId` = the recipient; destination `beacon`.

Contract rows: [`docs/contracts/updates-event-contract.json`](../contracts/updates-event-contract.json).
