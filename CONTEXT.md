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

## Public web entry

**Public root (`/`)**:
The main entry URL on the public host. Shows the full product when a valid **browser session** exists; otherwise shows the invite-only **landing surface**.

**Browser session**:
Server-owned sign-in state carried by an HttpOnly cookie on the public host. Not the same as a device seed or a short-lived API bearer token.

**Landing surface**:
Lightweight static HTML/JS for invite preview and sign-in entry (`/invite/…`, and `/` when signed out).

**WASM surface**:
The Flutter web application (`/` when a session cookie is present; deep app routes always).

**Basic invite URL**:
The shareable public invite entry (`/invite/<code>`). It is the URL users copy,
share, and open from messages; it is not itself the signup or accept operation.

**Signup-with-invite route**:
The onboarding route (`/sign/up/<code>`) for a user who arrived from a **basic
invite URL** without an authenticated account/session. On native it shows the
register screen and the server consumes the invite during account creation; on
web it defers to the **landing surface** (which owns signup). Future onboarding
may move into landing so the **WASM surface** can preload during it.

**Accept-invite route**:
The authenticated route (`/accept-invite/<code>`) for accepting a basic invite as
an existing, already-signed-in user who is not yet connected. This is the only
client route that mutates the social graph for invites, after the current account
is known and confirmation is complete. New users never use it (the server already
consumed their invite at signup).

**Flow reference**:
End-to-end routing (landing preview → WASM hash links → native deep links →
accept/signup) is documented in
[`docs/invite-signup-landing-flow.md`](docs/invite-signup-landing-flow.md).

## Room coordination UI

**Promoted message**:
A room message that was turned into a coordination item (ask, blocker, promise, etc.). The message keeps a normal chat bubble; a **message lifecycle footer** shows promotion and, when terminal, resolution metadata. Tapping the footer opens the item thread.

**Coordination anchor event** (timeline notify row):
A separate room message inserted when an item’s status changes (or on promote). Rendered as a centered system timeline bar, not an inline item card. `system_payload.sourceMessageId` points at the promoted source; tapping the bar scrolls to that message.

**Message lifecycle footer**:
Three-case chrome under a promoted source: reactions + date; promotion row (avatar, kind, date → thread); optional resolution row when status is resolved/cancelled/superseded (from `system_payload.lastStatusEvent` on the source message). Distinct from mark-done (`semanticMarker == done`).
