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

**Manual invite entry**:
A root-only convenience on signed-out `/` where a visitor pastes an invite link
or code; the landing normalizes it and redirects to the **basic invite URL**
without consuming the invite.

**Signup-with-invite route**:
The onboarding route (`/sign/up/<code>`) for a user who arrived from a **basic
invite URL** without an authenticated account/session. On native it shows the
register screen and the server consumes the invite during account creation; on
web it defers to the **landing surface** (which owns signup). The landing
starts **background WASM asset warmup** immediately on load (`app_preload.js`).

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

## Beacon lineage

**Lineage** (internal/domain term):
A directed beacon-to-beacon relationship recording that a beacon was created from a previously visible beacon. Carried by nullable `lineage_parent_beacon_id` (immediate source) and `lineage_root_beacon_id` (ultimate ancestor) on the beacon. Used as a single user's local memory of a previous similar event — not a global audience, group, channel, series, or recommendation system.
_Avoid (user-facing)_: fork, series, channel, subscription, audience, category, recurring.

**Create from this beacon** (user-facing action):
Copies a visible beacon's reusable content into a new draft and sets that draft's lineage pointers. Any user who can see a beacon (any non-deleted state, including your own and your own drafts) may do this. The resulting beacon shows a generic clickable reference ("Created from a previous beacon") that navigates to the parent beacon by id; the parent's title is never fetched/shown on the child. Internal mutation name `beaconFork` is acceptable; never surface "fork" in UI.

**Lineage forward suggestions** (subjective):
A single forwarding user's rules-based, explainable suggested targets derived only from that user's own visible memory across the lineage (their own forwards, positive reviews, private tags, and downstream help they routed). Computed per `(current_user_id, draft_beacon_id, lineage_parent_beacon_id)`; never stored as an objective beacon property and never a "best candidates" list.
_Avoid_: best candidates, audience, subscribers, customers, channel, campaign.

## Room coordination UI

**Promoted message**:
A room message that was turned into a coordination item (ask, blocker, promise, etc.). The message keeps a normal chat bubble; a **message lifecycle footer** shows promotion and, when terminal, resolution metadata. Tapping the footer opens the item thread.

**Coordination anchor event** (timeline notify row):
A separate room message inserted when an item’s status changes (or on promote). Rendered as a centered system timeline bar, not an inline item card. `system_payload.sourceMessageId` points at the promoted source; tapping the bar scrolls to that message.

**Message lifecycle footer**:
Three-case chrome under a promoted source: reactions + date; promotion row (avatar, kind, date → thread); optional resolution row when status is resolved/cancelled/superseded (from `system_payload.lastStatusEvent` on the source message). Distinct from mark-done (`semanticMarker == done`).

## My desk (My Work)

**My desk** (user-facing; l10n `myWork`):
The signed-in user's work inbox tab — beacons they **authored** or **help-offered** on, with filters and sort. Not the public beacon catalog or another user's profile beacons.
_Avoid_: mixing with **Inbox** (forwards received from others).

**Active filter** (default):
Non-archived cards where the user participates in ongoing work — `authoredActive` and `helpOfferedActive` card kinds. Excludes **drafts** and **archived** items.
_Avoid_: using "active" to mean only `lifecycle.open`; pending review and closed-review-open remain here until archived.

**All filter** (non-archived superset):
Every non-archived card: active + **drafts** + help-offered/active authored rows from the init fetch. Placed in the filter menu after role-specific filters and before **Archived**.

**Drafts filter**:
Authored beacons in `draft` lifecycle only (`authoredDraft` card kind).

**Archived filter**:
Closed-lifecycle beacons (lazy fetch). Separate from active/all/drafts.

**Archived count hint**:
Deduped count of closed authored + help-offered beacon ids from the init query, shown before the lazy archive fetch completes. Used for empty-state shortcuts only when count > 0.

**Draft count** (UI):
Count of draft cards from the init fetch; empty-state shortcut only when count > 0.
