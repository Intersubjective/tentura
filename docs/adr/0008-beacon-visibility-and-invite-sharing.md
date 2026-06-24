# ADR 0008: Relationship-scoped beacon visibility and single-use beacon-invite sharing

Status: Accepted (2026-06-24). **Supersedes ADR 0004 Amendment A** (the "any authenticated user reads any non-draft beacon" model).

## Context

A privacy QA review found that knowing a beacon UUID was effectively a read capability: the Hasura `beacon` (and `beacon_help_offer`) select permissions use `filter: {}`, and several V2 paths (`beaconInvolvement`, `beaconDisplayStatuses`, default `getBeaconById`) carry no viewer gate. ADR 0004 Amendment A documented this world-readable model as intentional, but it contradicts the product promise that beacon reach is scoped by relationships, and it leaks the social/coordination graph (forwarders, "not interested" rejectors, committers) to any logged-in user with an id.

This ADR reverses that: beacon and involvement reads become **relationship-scoped**, sharing becomes **invite-based**, and MeritRank is confirmed as **not** a read gate.

## Decision

1. **Canonical visibility contracts.** A beacon `B`'s normal content is visible to user `V` iff any of:
   - `V` is the author;
   - `V` has an active (non-cancelled) `beacon_forward_edge` with `recipient_id = V`;
   - `V` is a beacon steward, a room-admitted participant, or an active `beacon_help_offer` author;
   - `V` is a **mutual friend** of the author (reciprocal `vote_user.amount > 0` both directions).

   Drafts (`state = 3`) are always author-only. Deleted beacons (`state = 2`) never expose normal content to non-authors; any deleted UX is a generic tombstone path/result, not the normal `beacon` row. **MeritRank is never part of this predicate** — it remains the forwarding-candidate gate only. An unconsumed beacon invite is **not** part of this `(beaconId, viewerId)` predicate because `invitation.invited_id` is null until consumption; invite codes are separate preview capabilities, and accepting the invite creates the forward edge that grants ordinary visibility.

2. **Domain owns the rule; SQL is the shared enforcement adapter.** The predicate is an enterprise business rule, so the server **domain** owns the contract: a pure `BeaconVisibility` policy over typed facts (`canReadContent`, `canReadInvolvement`, `canReadTombstone`, `canPreviewInvite`), plus a `BeaconAccessGuard` port that V2 use cases depend on (never calling SQL or repositories directly — per the repo's use-cases-use-ports-only rule). The data layer implements the port. The pragmatic compromise — accepted deliberately — is that the *enforcement* is a shared pair of Postgres functions `beacon_can_read_content` / `beacon_can_read_involvement`, reused by (a) the `BeaconAccessGuard` data adapter and (b) Hasura `beacon` / `beacon_help_offer` / `beacon_image` select permissions (so existing Hasura reads — profile list, My desk, inbox nested, graph focus — are gated with ~zero client query changes). Reciprocal mutual-friendship lives in SQL where it is natural rather than duplicated across Hasura bool-exps and Dart. A **parity test** asserts the SQL function and the Dart `BeaconVisibility` policy agree across the fact matrix, so the duplication cannot silently drift.

3. **Involvement scope.** `beacon_can_read_involvement` = content visibility plus the involved set **or** the author's mutual friends. The forwarder chain, rejections, help-offerers, watchers, and onward-forwarders follow this predicate. Deleted beacons return no involvement graph.

4. **Single-use beacon invites replace raw share links.** The beacon "Share / QR" action mints a single-use `invitation` row with `beacon_id` set and a stored nullable `parent_forward_edge_id` for chain provenance. Accepting it materializes a `beacon_forward_edge` sharer→invitee (chained to the sharer's own inbound edge when present), making the invitee an involved recipient. The beacon must still allow forwarding at both mint and accept time. New users who sign up via the link also get mutual friendship with the sharer (normal onboarding); existing users get beacon access only. The legacy world-readable `/shared/view?id=B…` path is retired.

5. **Notifications gated by filter-at-read.** The Notification Center feed and email digest are filtered server-side by `beacon_can_read_content` at fetch/send time, so notifications about a beacon a user can no longer see disappear (covers delete, forward-cancel, un-friend, invite expiry). Deleted beacons may render only generic tombstones. Out-of-scope deep links re-fetch through the gated path and render a clean "no longer available" state (fixing the app-bar title leak). Already-delivered OS pushes are not recalled (impossible); payloads stay excerpt-only + lock-screen-safe.

6. **Secondary hardening, same principle.** Gate `beacon_help_offer` messages and `rejected_user_ids` to the involvement predicate; add sender-eligibility (`canReadContent` plus lifecycle `allowsForward`) and parent-edge validation to the forward mutation; remove or strictly lock down direct Hasura `beacon_forward_edge` insert.

## Consequences

- Beacon ids/URLs are no longer read capabilities; pasted raw links to out-of-scope beacons show "not available".
- Old clients assume world-readable beacons and will show empty/broken beacon views once the gate lands — this is a **breaking** change, so `MIN_CLIENT_VERSION` is bumped (per `versioning.mdc`).
- ADR 0004's `beaconFork` / `beaconLineageForwardSuggestions` visibility gate (Amendment A) is replaced by `canReadContent` / `beacon_can_read_content`; lineage source visibility now uses the same predicate instead of "reject deleted + others' drafts".
- Hasura permission filters referencing the predicate function with the session user must use Hasura's computed-field/session-argument mechanism; this is the main implementation risk to validate early.

## Alternatives considered

- **Pure Hasura boolean-expression permissions (no SQL function)** — rejected: reciprocal mutual-friendship and chain checks become gnarly and duplicated across V1 and Dart, risking drift on a security-critical gate.
- **Migrate all beacon reads off Hasura into gated V2 use cases** — rejected for now: architecturally cleaner but a large client+server migration; the SQL-predicate approach reuses existing Hasura read paths.
- **Keep ADR 0004's id-capability model and add only UI copy** — rejected: does not fix the leak.
