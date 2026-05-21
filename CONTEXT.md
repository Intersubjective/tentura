# Tentura

Coordination product for beacons (needs), rooms, and helpers.

## Language

**Current line**:
A short shared orientation string on a beacon’s room state: what is next, what is waited on, or the current coordination focus right now.
_Avoid_: Plan (reserved for a future full checklist/route object and for coordination-item Plan entities).

**Plan** (coordination item):
A structured coordination object (root plan and steps) on the Items tab—not the same as the current line on `BeaconRoomState`.
_Avoid_: Using “plan” in UI for the NOW orientation field.

## Relationships

- A **Beacon** has at most one **current line** on **BeaconRoomState** (room-private).
- Publishing or updating a root coordination **Plan** may sync text into the **current line**; they remain distinct concepts.

## Room coordination UI

**Promoted message**:
A room message that was turned into a coordination item (ask, blocker, promise, etc.). The message keeps a normal chat bubble; a **message lifecycle footer** shows promotion and, when terminal, resolution metadata. Tapping the footer opens the item thread.

**Coordination anchor event** (timeline notify row):
A separate room message inserted when an item’s status changes (or on promote). Rendered as a centered system timeline bar, not an inline item card. `system_payload.sourceMessageId` points at the promoted source; tapping the bar scrolls to that message.

**Message lifecycle footer**:
Three-case chrome under a promoted source: reactions + date; promotion row (avatar, kind, date → thread); optional resolution row when status is resolved/cancelled/superseded (from `system_payload.lastStatusEvent` on the source message). Distinct from mark-done (`semanticMarker == done`).
