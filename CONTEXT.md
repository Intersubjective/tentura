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
