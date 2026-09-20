# Constellation — product spec (as shipped)

User-facing behavior of **Constellation**: an ego-centred map (and accessible text alternative) of the **discoverable field of active requests** among mutually visible peers, with a personal arrangement of pinned people and requests. Internal wire name: `constellationField`. For architecture and algorithm contracts, see [`../plans/constellation-edge-semantics.md`](../plans/constellation-edge-semantics.md). For product direction, see [`../Tentura_current_status_quo.md`](../Tentura_current_status_quo.md).

## What Constellation is

Constellation answers: *"What is happening among my trusted connections, and how can I help?"* without requiring someone to forward a request to me first.

It is **not** a feed, ranking surface, or recommendation engine. It is a **snapshot map** of current opportunities, refreshed when opened.

| Surface | Meaning | Push/pull |
|---------|---------|-----------|
| **Inbox** | Requests explicitly forwarded to me, plus attention receipts (Receipts tab) | Push — someone chose me |
| **Constellation** | Requests I can discover in my relational field | Pull — I am looking |
| **My Work** | Requests I authored or offered help on | Pull on my responsibility |

A request can appear in Constellation **and** already be held (authored, offered on, forwarded, or joined as a participant). Field membership and held state are independent (D16).

Alongside the automatic field, each account can pin a person or a request at a chosen map position. Pins are private presentation choices: they do not change discoverability, permissions, discussion admission, or anyone else's Constellation.

## Home navigation

Bottom navigation (default tab: **My Work**):

| Tab | Role |
|-----|------|
| **My Work** | Requests I authored and/or offered help on |
| **Inbox** | Forwarded to me — Needs me, Watching, Receipts |
| **Constellation** | Discoverable field map / text view |
| **Friends** | Network / forward targets |
| **Profile** | Account, capabilities, settings |

Constellation occupies the slot formerly used by **Updates** (D17). Updates history lives under Inbox → **Receipts**. The Constellation nav item carries **no badge or unread count** (§9.2).

**My Work** empty state includes a prominent **Find ways to help** entry to Constellation (UX7).

## Discoverability (author control)

Active, published requests are **discoverable by default** to everyone mutually visible with the author. The author may opt out per request via **Let people find this request** on create/edit (**Info** tab → Details card). Authors change discoverability on published requests through **edit mode** today — there is no inline toggle on the published request view screen yet (see Limitations).

Discoverability widens the shared content read wall (`beacon_can_read_content`, m0162). Discovery grants the same content reads and operation eligibility as a forward recipient, but **does not** grant involvement visibility or discussion admission.

Migrations: **m0160** (`is_discoverable`), **m0161** (symmetric visibility), **m0162** (read wall), **m0163** (trust edges), **m0163a** (visibility cache).

## Map surface

### Layout

- **Ego** sits at the centre; **people** occupy concentric rings outward by path depth.
- Each person's **active discoverable requests** hang off them as satellite nodes.
- **Pinned people and requests** retain the viewer's chosen positions across sessions and devices. Pinning a person does not pin or move that person's requests; each request has its own pin.
- **Residual ring:** mutually visible peers with no drawable path within the hop cap still appear on an outer ring with their requests — tappable, but without a drawn explanation path (D3).
- **Forward edges are never drawn** (D5). A forwarded request belongs in Inbox, not as a discovery path.

### Edge vocabulary (legend)

| Legend label | Meaning |
|--------------|---------|
| **Direct connection** | Tier-1 explicit-trust path segment (`vote_user`, amount > 0) |
| **Indirect connection** | Tier-2 derived-trust fallback segment (dashed; unlabelled evidence — D1a) |
| **Request link** | Attachment from author to their request satellite |
| **Wider network reach** | Residual-ring stub — peer is visible, path not drawn (dashed) |

Tier-2 edges are visually distinct and carry **no label** about what evidence produced them.

### Interaction

- Tap a **request** → preview sheet (need, timing, coverage, connection copy, held-state actions).
- Tap a **person** → person panel with their discoverable requests (expand/collapse per person).
- **Filter bar** above the map: capability, location presence, timing, include-unspecified toggle.
- **Overflow groups** per author when label budget hides satellites (`+N more`); an expanded author's group becomes a **"Show fewer"** control so expansion is reversible from the map itself.
- **Snapshot bar:** load timestamp, Map/Text switch, refresh control.
- **Camera recovery:** "Show whole field" fits every currently placed node into view (never above scale 1.0); "Center view" recentres on the viewer at scale 1.0. Neither moves pins, filters, selection, or expansion state. Opening the Field, changing filters, expanding/collapsing an author, and switching Map/Text never move the camera on their own.
- **Pin controls:** dropping an unpinned person or request pins it immediately at the drop coordinate. Moving an already pinned target saves its final position on drop; unpin removes only that account's placement and re-layouts that node into the automatic layer.
- Actions revalidate current permissions and request state before offer/forward submission (UX8); stale snapshot shows recovery copy and refresh.

### Pinned placement and request state

Pins belong to the viewing account and describe a stable personal map. They may overlap; the most recently stored placement is drawn and tapped on top. This overlap allowance is for pins only — automatic placement keeps every unpinned node's readable footprint (body, label, badges) clear of avoidable overlap with other placed nodes, including its own author. A pin is not a saved request: **Favorites** and Constellation pins are independent actions.

If a pinned request is temporarily outside the active field, its placement remains stored. **Show closed** can reveal readable wrapping-up and closed requests, while cancelled, deleted, unpublished, blocked, and otherwise unreadable requests never render. When an eligible request returns, it returns at its saved position. A pinned person may remain even when that person currently has no active readable requests.

Request state is visible in both Map and Text views. The legend pairs each state with text and a non-colour marker: Open, Needs more help, Enough help, Wrapping up, and Closed. The pin glyph identifies placement only; it does not imply participation or priority.

### Filters (UX4)

- **Capability** — multi-select from slugs present in the loaded field.
- **Location** — filters on requests that **establish presence** via location fields (lat/long or address label). A request **without** location data is *unspecified*, never treated as "remote."
- **Timing** — event (start set), deadline (end only), undated, or within-N-days variants where schedule data exists.
- **Include unspecified** — whether requests missing filter-relevant data pass capability/location/timing filters.
- **Show closed** — includes readable wrapping-up and closed requests; it does not include cancelled requests.
- **Only Requests I participated in** — includes requests the viewer authored, currently or historically participated in, or has a valid pending help offer for. A forward by itself does not count; a declined offer without participation does not count.

Filters preserve person pins and stored request pins. A request filter can hide a pinned request without deleting its placement; the controls report how many pinned requests are currently hidden and offer a clear-filter action. Map and Text views expose the same eligible request ids for each filter state.

There is **no effort filter** — effort is not a reliable authorized field in v1.

### Density (UX5)

Label budget scales with viewport area and a dimensionless text-scale ratio (not a font size), and is applied consistently to every composition — the first load and every later recompose (filter change, expand/collapse, tab reselect) use the same budget. When the budget is exceeded, requests group under per-author overflow controls. Field-level notices explain peer cap, request cap, and client render cap when truncation applies.

Labels, overflow chips, and the pin/status badges render as a screen-space overlay layer above the camera-transformed graph, so they stay at their configured size (and text stays legible) regardless of camera zoom. Pin and status badges sit at the node's top corners and never cover its label.

### Positional stability (narrowed A3)

Within the **same sector** (same parent branch), person positions are stable across filter changes. Stability is **vacuous at depth 1** (direct peers). Peers in the **residual ring** outside a sector's subtree may shift when filters change. Requests that change **holder status** (e.g. newly held) may move between author satellites and ego's centre.

## Text view (UX6)

Accessible alternative using the **same snapshot, filters, pins, and request set** as the map — not a ranked list or infinite scroll. Plain-list mode (when peer cap truncates paths) suppresses per-request connection copy in text view only; the map still shows path notices with a link to switch views. Text rows expose pin state and lifecycle state in their accessible labels.

Keyboard and screen-reader users can complete the same filter, selection, preview, and view-mode tasks as on the map.

## Freshness (D15, UX8)

- Field loads **once on open**; no realtime invalidation for discovery-only viewers.
- Private anchor changes are the narrow exception: a pin, move, unpin, or target cascade refreshes the viewer's anchor projection so their own open Constellation sessions converge. It carries no newly authorized request or person data.
- Snapshot timestamp is shown; user may refresh manually.
- Before offer/forward, client preflights involvement and server validates `expectedOfferKind` inside the mutation transaction.
- Coverage changes after snapshot (e.g. enoughHelp) prompt backup choice — never silent conversion.

## Social meaning (UX3)

- **Connection** (path or residual visibility) ≠ **referral** (someone forwarded to you) ≠ **participation** (you offered, were admitted, or forwarded).
- Preview copy states when a connection is **not a referral**.
- Unauthorized involvement never appears in discovery payloads or previews; discussion content never leaks as discovery context.

## UX acceptance fixtures (UX9 — overseer)

The following fixture shapes are **constructible** on a local dev stack (Postgres + MeritRank + server + client) using the patterns in `packages/server/test/data/repository/constellation_field_repository_pg_test.dart` and QA API routes. This documents readiness for the overseer's task-based study — **no study results are recorded here.**

| Fixture element | How to construct |
|-----------------|------------------|
| **Explicit connection** | Reciprocal `vote_user` trust between ego and peer; tier-1 path draws on map |
| **Inferred connection** | Mutual visibility via MeritRank only (one-way explicit trust + MR reverse); tier-2 dashed segment or residual ring |
| **Genuine referral** | Separate `beacon_forward_edge` to ego — item appears in **Inbox**, not drawn as Constellation path |
| **Pending helper** | Ego has `beacon_help_offer` status pending on a discoverable request |
| **Acknowledged helper** | Author responded `useful` / `needCoordination`; held state `participant` or `offered` |
| **Unknown effort/timing** | Published request with null schedule fields and no effort metadata |
| **enoughHelp request** | `beacon.status = 8`; de-emphasised label; backup offer kind on new offers |
| **Dense field** | Many reciprocal-trust peers each with discoverable requests (pg test uses capped fixtures; local QA can scale via scripted user/beacon creation) |
| **Compact / large layouts** | Resize browser viewport below/above 600px width; text scale via OS/browser settings |
| **Text view** | Map/Text switch in snapshot chrome — same data, filter parity |

**Study task (overseer only):** *"Find something you could help with, explain your connection to its author, and describe what happens if you offer."* Plus stale-request recovery and keyboard/screen-reader operation. Record completion time, taps, mistaken endorsement assumptions, and offer-vs-admission understanding — do **not** treat clicks or browsing duration alone as success.

## Limitations (v1)

Shipped behavior deliberately excludes or narrows the following. Do not "fix" these without a new architecture decision.

1. **No effort filter** — effort is not an authorized, reliable field for filtering.
2. **No third-party participation statements** — previews show the viewer's own held state only; other helpers' involvement is not disclosed in discovery payloads.
3. **Actions outlive discoverability (R7)** — help offers, forwards, invites, and forks taken while a request was discoverable remain valid after the author opts out.
4. **Already-served media is not revocable (R8)** — tightening discoverability does not invalidate URLs already served under prior read access.
5. **Positional stability narrowed (§0.4 / A3)** — four explicit narrowings: sector containment only; vacuous at depth 1; residual ring peers outside a sector may shift; requests changing holder status may move between ego centre and author satellites.
6. **Symmetric-visibility residual gap (§0.1 / N1)** — field membership is a **subset** of wall-readable, never a superset. A peer whose MeritRank walk reaches ego but who is not enumerable from ego's candidate list without an unbounded scan may have readable requests that do not appear in the field. Display gap only — not an authorization leak.
7. **Stage-2 reachability cost (`ALG-STAGE2`)** — a holder whose only route needs a tier-2 (`T`) node at a ring other than its explicit-trust depth-1 falls to the **residual ring** although a path exists, because one person is never drawn at two rings.
8. **No remote filter** — location fields establish **presence** only; absence of location means *unspecified*, never "remote."
9. **Discoverability toggle on view screen** — authors reach the control via create/edit (`BeaconCreateRoute(editId:)`); published request view does not mount `BeaconDiscoverabilityControl` yet. Reusable widget exists for a future mount.

**Follow-ups (deferred, not narrowed contracts):** general edge-detour routing (labels moved to an opaque screen-space layer instead, so edges never show through label text — automatic placement still prefers candidates whose attachment line does not cross another body, but full rerouting around obstacles is out of scope for this pass).

## Related docs

- Architecture: [`../plans/constellation-edge-semantics.md`](../plans/constellation-edge-semantics.md)
- Implementation evidence: [`../plans/constellation-implementation-journal.md`](../plans/constellation-implementation-journal.md)
- Visibility matrix: [`../beacon-visibility-matrix.md`](../beacon-visibility-matrix.md)
