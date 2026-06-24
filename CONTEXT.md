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

## Beacon visibility & sharing

**Beacon visibility** (who can SEE a beacon):
A beacon's normal content is visible to a user V iff any of: V is the **author**; V has an active (non-cancelled) **forward edge** as recipient; V is a **room-admitted participant** or active **help-offerer**; or V is a **mutual friend** of the author (reciprocal `vote_user.amount > 0` both directions). Mutual-friend visibility covers all of the author's **non-draft, non-deleted** beacons (open, wrapping-up, closed, cancelled), but actual actions remain limited by lifecycle (e.g. forwarding only while the beacon allows forwarding). **Drafts** are always author-only. **Deleted** beacons never expose normal content to non-authors; use generic tombstones only. **MeritRank is never a visibility gate** — it is used only as the forwarding-candidate gate.
_Avoid_: treating a beacon id/URL as a read capability; using MeritRank score or path distance to decide who can read a beacon.

**Involvement visibility** (who can see WHO is involved):
The forwarder chain, "not interested" rejections, help-offerers, watchers, and onward-forwarders of a non-deleted beacon are visible to **involved** users (author + anyone on a forward edge + help-offerers/room participants) **and** to the author's **mutual friends**.

**Beacon invite** (single-use share):
A "Share / QR" action on a beacon mints a **single-use** `invitation` row carrying that `beacon_id` (7-day TTL, revocable before use, consumed on accept). The invite code is a separate preview capability, not general beacon visibility: raw `beacon_by_pk` remains denied until the invite is accepted. The **sharer** is whoever generated the link (author or an onward forwarder); their own inbound forward edge is the **parent** for chain integrity. Accepting always materializes a **forward edge** sharer→invitee (invitee becomes an involved recipient: can see / commit / forward while lifecycle permits, and appears in the forward graph). A **new** user who signs up via the link also gets **mutual friendship** with the sharer; an **existing** user gets beacon access only (no forced friendship).
_Avoid_: the legacy raw `/shared/view?id=B…` link that exposed a world-readable beacon view; multi-use beacon share links.

**Beacon-invite tracking**:
Beacon invites are tracked in the **Friends → Invitations** surface, split into a **People** subsection (plain Tentura invites) and a **Beacon invites** subsection (grouped by beacon, showing beacon title + target). The beacon's share sheet also lists/regenerates that beacon's own pending links.

## Room coordination UI

**Promoted message**:
A room message that was turned into a coordination item (ask, blocker, promise, etc.). The message keeps a normal chat bubble; a **message lifecycle footer** shows promotion and, when terminal, resolution metadata. Tapping the footer opens the item thread.

**Coordination anchor event** (timeline notify row):
A separate room message inserted when an item’s status changes (or on promote). Rendered as a centered system timeline bar, not an inline item card. `system_payload.sourceMessageId` points at the promoted source; tapping the bar scrolls to that message.

**Message lifecycle footer**:
Three-case chrome under a promoted source: reactions + date; promotion row (avatar, kind, date → thread); optional resolution row when status is resolved/cancelled/superseded (from `system_payload.lastStatusEvent` on the source message). Distinct from mark-done (`semanticMarker == done`).

## Beacon lifecycle

**Close** (author intent):
The author declaring a beacon **done / wrapped up** (a successful or neutral end of the work). Distinct from **Cancel**. Whether closing finalizes immediately or opens a **review window** depends only on participation (committers), never on naming. Never labels the result "cancelled".
_Avoid_: using "close" to mean "abandon"; conflating the close *intent* with the committer-count *mechanics*.

**Cancel** (author intent):
The author **calling the beacon off / retracting** it — an explicit abandon. A separate, deliberate action from **Close**, never auto-derived from committer count. Produces a distinct "cancelled" outcome. Offered **only when there are 0 committers**: once anyone commits, the author's sole end-path is **Close** → **Wrapping up** (committers are owed their review), so a committed beacon cannot be unilaterally cancelled.
_Avoid_: deriving "cancelled" automatically from no committers; offering Cancel once committers exist or during Wrapping up.

**Committer**:
A non-author user whose help offer the author has **acknowledged** — an active (non-withdrawn) `beacon_help_offer` whose author coordination response is `useful` or `needCoordination`. Offers that are **unacknowledged** (no response yet) or **rejected** (`overlapping`, `needDifferentSkill`, `notSuitable`) are NOT committers. Committer count (excluding the author and forwarders) decides the **mechanics** of **Close**, the **stakes gate** on Cancel/Delete, and who is a **required reviewer** for **Close now**.
_Assumption_: acknowledged = {`useful`, `needCoordination`}; narrow to `useful`-only if needed.
_Avoid_: counting every raw/active offer as a committer (rejected/unacknowledged offers don't grant stake).

**Closed** (outcome state):
A beacon the author **Closed** and is now done. Reached either immediately (Close with no committers) or after the review window ends. A single "done" outcome — the user-facing label does **not** distinguish whether a review happened.
_Avoid_: separate user-facing names for "closed without review" vs "closed after review".

**Cancelled** (outcome state):
A beacon the author explicitly **Cancelled** (called off). Only reached via the **Cancel** intent, never from committer count.

**Wrapping up** (status; internal `reviewOpen` / state 5):
The in-between after the author **Closes** a beacon that has committers: a time-boxed countdown (default 7 days) during which helpers reflect/evaluate and the author can still post updates and edit, but **no new help offers and no forwarding**. Ends by moving to **Closed**. Shown with a countdown banner that states the rules.
_Avoid_: "Review open" (opaque), or wording that implies moderation/approval gating.

**Close now** (early close during Wrapping up):
An author action available only when every **required reviewer** has **finished or skipped** their review (per-user review status in {finished, skipped}). **Required reviewers = the author + committers; forwarders are excluded** (a forwarder may review, but their pending review never blocks closure). It skips the remaining countdown and moves the beacon to **Closed**. Disabled (with explanation) while a required reviewer still has the review open, since the window protects committers' stake. Distinct from extending or reopening.
_Avoid_: an unconditional early-close button; letting a forwarder's pending review block Close now; closing while a committer still has their review pending.

**Extend review** (author action during Wrapping up):
Adds another 7 days to the countdown. Allowed at most **twice**. Additive and low-risk — no confirmation; the UI shows extensions remaining and the new close date.

**Reopen** (author action during Wrapping up):
Returns the beacon to **Open**, discarding the review window and its scaffolding and reverting the inbox/activity tombstones the close fired. Strong confirmation ("returns to Open and discards current review progress").

**Deleted** (removal state):
A beacon removed via Delete — not an outcome. **Delete is gated by stakes:** a beacon that **ever had an acknowledged committer** (an offer the author ever marked `useful`/`needCoordination`, even if later withdrawn) can never be deleted (the author uses **Archive** to clear it from their own desk). A bare offer-then-withdraw with no author acknowledgment does NOT lock Delete (anti-griefing). Drafts are destroyed permanently (hard delete: row + images). A published beacon that **never** had an acknowledged committer becomes a soft-deleted tombstone (state 2) for people who saw it.
_Avoid_: deleting a beacon that ever had an acknowledged committer; locking Delete on unacknowledged/rejected offers; treating Delete as a universal escape hatch that bypasses committer stake.

## My desk (My Work)

**My desk** (user-facing; l10n `myWork`):
The signed-in user's work inbox tab — beacons they **authored** or **help-offered** on, with filters and sort. Not the public beacon catalog or another user's profile beacons.
_Avoid_: mixing with **Inbox** (forwards received from others).

**Active filter** (default):
Non-archived cards (excluding **drafts** and deleted). Beacons of any lifecycle the user has not archived — including review-window and finished beacons — appear here until the user archives them.
_Avoid_: using "active" to mean only `lifecycle.open`; review-window and finished beacons remain here until archived.

**All filter** (non-archived superset):
Every non-archived card: active + **drafts** + help-offered/active authored rows from the init fetch. Placed in the filter menu after role-specific filters and before **Archived**.

**Drafts filter**:
Authored beacons in `draft` lifecycle only (`authoredDraft` card kind).

**Archived** (per-user flag):
A **per-user** filing flag, **orthogonal to lifecycle**. Any user may archive any beacon they can see, for themselves only; default is **not archived**. Archiving moves the beacon into that user's **Archived** filter; finished beacons do **not** auto-archive. Server-persisted per user; affects My desk sectioning only.
_Avoid_: equating "archived" with any `lifecycle` state (closed/cancelled/review-complete); a finished beacon stays in the main list until the user archives it.

**Archived filter**:
The user's own archived beacons (any lifecycle), lazy-fetched. Separate from active/all/drafts.

**Archived count hint**:
Deduped count of the user's archived beacon ids from the init query, shown before the lazy archive fetch completes. Used for empty-state shortcuts only when count > 0.

**Draft count** (UI):
Count of draft cards from the init fetch; empty-state shortcut only when count > 0.

**Finished card** (My desk):
A My desk card for a **Closed** or **Cancelled** beacon the user has **not** archived. Appears in **Active** and **All** (not only Archived), ranked at a bottom tier so live work stays on top, with a design-system **status indicator** (icon + "Closed"/"Cancelled" label, never color-only, never a `Chip`/pill) and a one-tap **Archive** affordance. A one-time inline hint explains finished beacons stay until archived.
_Avoid_: routing finished-but-unarchived beacons into the Archived filter (that coupling is removed); interleaving them with live work by recency.
